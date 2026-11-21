-- Effets : animation d'ouverture de caisse, pieces qui volent vers le compteur, eclats a la
-- destruction, chiffres de degats, onde de choc du boss, flashs (renaissance, voyage), sons,
-- mode performance.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local F = require(ReplicatedStorage.Shared.Formulas)
local Icons = require(ReplicatedStorage.Shared.Icons)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local UI = require(script.Parent.UI)
local State = require(script.Parent.State)
local HUD = require(script.Parent.HUD)
local RelicView = require(script.Parent.RelicView)
local Window = require(script.Parent.Window)

local Effects = {}
local C = UI.C
local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local SOUNDS = {
	coin = "rbxasset://sounds/electronicpingshort.wav",
	hit = "rbxasset://sounds/action_jump_land.mp3",
	whoosh = "rbxasset://sounds/swoosh.wav",
}

function Effects.Play(name, volume, pitch)
	local s = Instance.new("Sound")
	s.SoundId = SOUNDS[name] or name
	local sfx = State.data and State.data.Settings.Sfx or 0.7
	s.Volume = (volume or 0.5) * sfx
	s.PlaybackSpeed = pitch or 1
	s.Parent = SoundService
	s:Play()
	task.delay(4, function()
		s:Destroy()
	end)
end

local function burst(position, color, count, speed)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.Transparency = 1
	p.Size = Vector3.one
	p.CFrame = CFrame.new(position)
	p.Parent = workspace
	local e = Instance.new("ParticleEmitter")
	e.Rate = 0
	e.Lifetime = NumberRange.new(0.5, 1)
	e.Speed = NumberRange.new(speed * 0.5, speed)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Acceleration = Vector3.new(0, -30, 0)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
	e.LightEmission = 0.8
	e.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
	e.Parent = p
	e:Emit(State.data and State.data.Settings.LowGraphics and math.floor(count / 3) or count)
	task.delay(1.5, function()
		p:Destroy()
	end)
end

-- Piece a l'ecran qui vole vers le compteur
local function coinFly(worldPos, amount)
	local sp, on = camera:WorldToViewportPoint(worldPos)
	if not on then
		return
	end
	local img = Icons.Image("coin", HUD.Screen, { Size = UDim2.fromOffset(34, 34), Position = UDim2.fromOffset(sp.X, sp.Y), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 50 })
	local target = UDim2.new(0.5, -200, 0, 36)
	local tw = UI.tween(img, 0.55, { Position = target, Size = UDim2.fromOffset(22, 22) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	tw.Completed:Connect(function()
		img:Destroy()
	end)
end

local function floatingText(position, text, color, size)
	local a = Instance.new("Part")
	a.Anchored = true
	a.CanCollide = false
	a.CanQuery = false
	a.Transparency = 1
	a.Size = Vector3.one
	a.CFrame = CFrame.new(position + Vector3.new(math.random(-15, 15) / 10, 0, math.random(-15, 15) / 10))
	a.Parent = workspace
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(160, 50)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.Adornee = a
	bb.Parent = a
	local t = UI.text({ Size = UDim2.fromScale(1, 1), Text = text, TextColor3 = color, StrokeThickness = 3 }, bb)
	UI.tween(a, 0.9, { CFrame = a.CFrame + Vector3.new(0, 4, 0) })
	task.delay(0.5, function()
		UI.tween(t, 0.4, { TextTransparency = 1 })
	end)
	task.delay(1, function()
		a:Destroy()
	end)
end

-- Chiffres de degats : on suit la vie de la cible visee par le joueur
local lastHP = {}
local function watchDamage()
	local targets = workspace:WaitForChild("Targets")
	game:GetService("RunService").Heartbeat:Connect(function()
		local name = player:GetAttribute("Target")
		local m = name and targets:FindFirstChild(name)
		if not m then
			return
		end
		local hp = m:GetAttribute("HP")
		local prev = lastHP[m]
		lastHP[m] = hp
		if prev and hp and hp < prev and m.PrimaryPart then
			Effects.Play("hit", 0.25, 1 + math.random() * 0.4)
			if State.data and State.data.Settings.DamageNumbers ~= false then
				floatingText(m.PrimaryPart.Position + Vector3.new(0, m.PrimaryPart.Size.Y / 2 + 1, 0), "-" .. F.Format(prev - hp), Color3.fromRGB(255, 230, 120))
			end
			burst(m.PrimaryPart.Position + Vector3.new(0, m.PrimaryPart.Size.Y * 0.3, 0), C.Gold, 6, 10)
		end
	end)
end

-- Ouverture de caisse ----------------------------------------------------------------------------------
local function crateAnimation(results)
	Window.Close()
	local overlay = UI.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1, ZIndex = 80 }, HUD.Screen)
	UI.tween(overlay, 0.25, { BackgroundTransparency = 0.35 })
	local crate = Icons.Image("crate", overlay, { Size = UDim2.fromOffset(220, 220), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 81 })
	-- tremblement de plus en plus fort
	for i = 1, 10 do
		crate.Rotation = (i % 2 == 0 and 1 or -1) * i * 1.5
		crate.Size = UDim2.fromOffset(220 + i * 4, 220 + i * 4)
		Effects.Play("hit", 0.2, 0.8 + i * 0.05)
		task.wait(0.08)
	end
	local flash = UI.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0, ZIndex = 90 }, overlay)
	UI.tween(flash, 0.5, { BackgroundTransparency = 1 })
	crate:Destroy()
	Effects.Play("whoosh", 0.6, 1)
	local n = #results
	local cards = {}
	for i, r in ipairs(results) do
		local def = Config.RelicById[r.id]
		local rar = Config.RarityById[def.rarity]
		local x = (i - (n + 1) / 2) * 250
		local card = UI.new("Frame", { Size = UDim2.fromOffset(230, 300), Position = UDim2.new(0.5, x, 0.5, 0), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, ZIndex = 82 }, overlay)
		-- rayons tournants a la couleur de la rarete
		local rays = UI.new("Frame", { Size = UDim2.fromOffset(300, 300), Position = UDim2.fromScale(0.5, 0.4), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, ZIndex = 82 }, card)
		for k = 0, 7 do
			local ray = UI.new("Frame", { Size = UDim2.fromOffset(26, 300), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), Rotation = k * 22.5, BackgroundColor3 = rar.color, BackgroundTransparency = 0.55, BorderSizePixel = 0, ZIndex = 82 }, rays)
			UI.gradient(ray, Color3.new(1, 1, 1), Color3.new(1, 1, 1), 90).Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 1) })
		end
		TweenService:Create(rays, TweenInfo.new(6, Enum.EasingStyle.Linear, Enum.EasingDirection.In, -1), { Rotation = 360 }):Play()
		RelicView.Icon(r.id, card, { Size = UDim2.fromOffset(200, 200), Position = UDim2.new(0.5, -100, 0.4, -100), ZIndex = 84 }, false, true)
		UI.text({ Size = UDim2.new(1, 0, 0, 34), Position = UDim2.new(0, 0, 1, -92), Text = def.name, ZIndex = 85, StrokeThickness = 3 }, card)
		UI.text({ Size = UDim2.new(1, 0, 0, 28), Position = UDim2.new(0, 0, 1, -56), Text = rar.name .. "  -  P " .. F.Format(def.power), TextColor3 = rar.color, ZIndex = 85, StrokeThickness = 3 }, card)
		if r.first then
			local new = UI.text({ Size = UDim2.new(1, 0, 0, 30), Position = UDim2.new(0, 0, 0, -10), Text = "NOUVEAU !", TextColor3 = C.Gold, ZIndex = 86, StrokeThickness = 3, Rotation = -8 }, card)
		end
		if not r.uid then
			UI.text({ Size = UDim2.new(1, 0, 0, 24), Position = UDim2.new(0, 0, 1, -26), Text = "Inventaire plein !", TextColor3 = C.Red, ZIndex = 85 }, card)
		end
		local s = UI.new("UIScale", { Scale = 0.2 }, card)
		UI.tween(s, 0.4 + i * 0.08, { Scale = 1 }, Enum.EasingStyle.Back)
		table.insert(cards, card)
		if rar.index >= 5 then
			Effects.Play("coin", 1, 0.6)
			task.delay(0.15, Effects.Play, "coin", 1, 0.9)
			task.delay(0.3, Effects.Play, "coin", 1, 1.3)
		end
	end
	local hint = UI.text({ Size = UDim2.fromOffset(400, 30), Position = UDim2.new(0.5, -200, 1, -60), Text = "Clique pour continuer", TextColor3 = C.Sub, ZIndex = 85 }, overlay)
	local closed = false
	local function close()
		if closed then
			return
		end
		closed = true
		UI.tween(overlay, 0.2, { BackgroundTransparency = 1 })
		for _, c in ipairs(cards) do
			UI.tween(c:FindFirstChildOfClass("UIScale"), 0.2, { Scale = 0 })
		end
		task.wait(0.22)
		overlay:Destroy()
	end
	local btn = UI.new("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", ZIndex = 95 }, overlay)
	btn.Activated:Connect(close)
	task.delay(4.5, close)
end

local function screenFlash(color, t)
	local f = UI.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = color, BackgroundTransparency = 0.2, ZIndex = 70 }, HUD.Screen)
	UI.tween(f, t or 0.8, { BackgroundTransparency = 1 })
	task.delay(t or 0.8, function()
		f:Destroy()
	end)
end

local function shockwave(position, radius)
	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromRGB(200, 120, 255)
	ring.Transparency = 0.3
	ring.Size = Vector3.new(0.4, 4, 4)
	ring.CFrame = CFrame.new(position + Vector3.new(0, 0.6, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = workspace
	UI.tween(ring, 0.6, { Size = Vector3.new(0.4, radius * 2, radius * 2), Transparency = 1 })
	task.delay(0.7, function()
		ring:Destroy()
	end)
end

local function applySettings()
	local s = State.data and State.data.Settings
	if not s then
		return
	end
	Lighting.GlobalShadows = not s.LowGraphics
	local music = SoundService:FindFirstChild("RelicMusic")
	if music then
		music.Volume = (s.Music or 0.5) * 0.5
	end
end

function Effects.Init()
	if Config.MusicId and Config.MusicId ~= "" then
		local m = Instance.new("Sound")
		m.Name = "RelicMusic"
		m.SoundId = Config.MusicId
		m.Looped = true
		m.Volume = 0.25
		m.Parent = SoundService
		m:Play()
	end
	State.Changed.Event:Connect(function(what)
		if what == "data" then
			applySettings()
		end
	end)
	task.spawn(watchDamage)
	Remotes.FX.OnClientEvent:Connect(function(kind, d)
		d = d or {}
		if kind == "Coin" then
			Effects.Play("coin", 0.35, 1.2 + math.random() * 0.3)
			coinFly(d.position, d.amount)
		elseif kind == "Break" then
			burst(d.position + Vector3.new(0, 2, 0), C.Gold, 30, 25)
			Effects.Play("hit", 0.5, 0.7)
		elseif kind == "CrateOpen" then
			task.spawn(crateAnimation, d.results)
		elseif kind == "Shockwave" then
			shockwave(d.position, d.radius)
			Effects.Play("whoosh", 0.7, 0.6)
		elseif kind == "BossDown" then
			burst(d.position, Color3.fromRGB(200, 120, 255), 80, 40)
		elseif kind == "BossReward" then
			HUD.Big(d.boss .. " vaincu !", "+" .. F.Format(d.coins) .. " pieces (" .. math.floor(d.share * 100) .. " % des degats)" .. (d.relic and "  + RELIQUE DU BOSS !" or ""), Color3.fromRGB(215, 160, 255))
		elseif kind == "Teleport" or kind == "WorldUnlock" then
			screenFlash(Color3.fromRGB(150, 200, 255), 0.8)
			Effects.Play("whoosh", 0.8, 1)
			if kind == "WorldUnlock" then
				HUD.Big("Nouveau monde !", Config.WorldById[d.world].name, C.Gold)
			end
		elseif kind == "Rebirth" then
			screenFlash(Color3.fromRGB(190, 90, 255), 1.2)
			HUD.Big("RENAISSANCE " .. d.count, "Bonus permanents augmentes !", Color3.fromRGB(215, 160, 255))
		elseif kind == "Upgrade" or kind == "Purchase" then
			Effects.Play("coin", 0.6, 1.5)
			if kind == "Purchase" then
				HUD.Toast(d.name .. " achete !", "good")
			end
		elseif kind == "Daily" then
			HUD.Big("Jour " .. d.day .. " !", d.text, C.Green)
		elseif kind == "Reward" then
			HUD.Big(d.title, d.text, C.Gold)
		elseif kind == "TradeDone" then
			HUD.Big("Echange reussi !", "Tes nouvelles reliques sont dans l'inventaire", C.Green)
		end
	end)
end

return Effects
