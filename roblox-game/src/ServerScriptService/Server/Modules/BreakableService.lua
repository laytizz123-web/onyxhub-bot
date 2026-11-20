-- Objets a casser (tirelires, cristaux, cadeaux geants) : nouvelle facon de gagner des coins.
-- Le joueur clique sur un objet : ses pets equipes vont l'attaquer (animation cote client).
-- Les degats dependent du nombre et de la puissance des pets. A la casse, chaque joueur qui a
-- participe recoit des coins en proportion de ses degats.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local DataService = require(script.Parent.DataService)
local MapBuilder = require(script.Parent.MapBuilder)
local PetService = require(script.Parent.PetService)

local BreakableService = {}

local CFG = Config.Breakables
local folder
local breakables = {} -- [Model] = { zone, type, hp, maxHp, reward, hits = {[player] = degats}, bar, label }
local counter = 0

local ZONE_TINT = {
	Village = { crystal = Color3.fromRGB(120, 220, 255), gift = Color3.fromRGB(255, 90, 140), ribbon = Color3.fromRGB(255, 220, 70) },
	Foret = { crystal = Color3.fromRGB(110, 255, 140), gift = Color3.fromRGB(150, 90, 255), ribbon = Color3.fromRGB(120, 255, 200) },
	Desert = { crystal = Color3.fromRGB(255, 180, 60), gift = Color3.fromRGB(40, 110, 230), ribbon = Color3.fromRGB(255, 210, 60) },
}

local function part(model, props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in pairs(props) do
		p[k] = v
	end
	p.Parent = model
	return p
end

local function buildPiggy(model, base)
	local pink = Color3.fromRGB(255, 150, 190)
	local dark = Color3.fromRGB(230, 110, 160)
	part(model, { Shape = Enum.PartType.Ball, Size = Vector3.new(4.6, 4.6, 4.6), CFrame = base * CFrame.new(0, 2.7, 0), Color = pink })
	part(model, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.8, 1.7, 1.7), CFrame = base * CFrame.new(0, 2.5, -2.45) * CFrame.Angles(0, math.rad(90), 0), Color = dark })
	for _, x in ipairs({ -0.35, 0.35 }) do
		part(model, { Shape = Enum.PartType.Ball, Size = Vector3.new(0.35, 0.45, 0.2), CFrame = base * CFrame.new(x, 2.5, -2.88), Color = Color3.fromRGB(150, 60, 100) })
		part(model, { Shape = Enum.PartType.Ball, Size = Vector3.new(0.75, 0.75, 0.75), CFrame = base * CFrame.new(x * 3.2, 3.6, -1.85), Color = Color3.fromRGB(30, 25, 40) })
		part(model, { Shape = Enum.PartType.Ball, Size = Vector3.new(0.25, 0.25, 0.25), CFrame = base * CFrame.new(x * 3.2 - 0.12, 3.75, -2.17), Color = Color3.new(1, 1, 1), Material = Enum.Material.Neon })
		part(model, { Size = Vector3.new(1, 1.1, 0.35), CFrame = base * CFrame.new(x * 4, 4.85, -0.6) * CFrame.Angles(math.rad(-15), 0, math.rad(x * 60)), Color = dark })
	end
	for _, x in ipairs({ -1.2, 1.2 }) do
		for _, z in ipairs({ -1.1, 1.1 }) do
			part(model, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(1, 1.1, 1.1), CFrame = base * CFrame.new(x, 0.5, z) * CFrame.Angles(0, 0, math.rad(90)), Color = dark })
		end
	end
	part(model, { Size = Vector3.new(1.4, 0.15, 0.3), CFrame = base * CFrame.new(0, 5.0, 0), Color = Color3.fromRGB(60, 30, 50) })
	part(model, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, 1.1, 1.1), CFrame = base * CFrame.new(0, 5.35, 0) * CFrame.Angles(0, math.rad(90), 0), Color = Config.Colors.Gold, Material = Enum.Material.Neon })
	return Vector3.new(5, 5.6, 5.6)
end

local function buildCrystal(model, base, color)
	part(model, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(1, 4.5, 4.5), CFrame = base * CFrame.new(0, 0.5, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(120, 115, 130), Material = Enum.Material.Slate })
	local spikes = { { 0, 0, 0, 5.5, 1.7 }, { 1.1, 0.4, 25, 3.6, 1.2 }, { -1.1, -0.3, -25, 3.8, 1.25 }, { 0.2, 1.1, 0, 3.2, 1.1 }, { -0.4, -1.1, -12, 3, 1 } }
	for i, s in ipairs(spikes) do
		local x, z, tilt, h, w = s[1], s[2], s[3], s[4], s[5]
		local cf = base * CFrame.new(x, 1, z) * CFrame.Angles(math.rad(z * 12), 0, math.rad(tilt)) * CFrame.new(0, h / 2, 0) * CFrame.Angles(0, math.rad(45), 0)
		part(model, { Size = Vector3.new(w, h, w), CFrame = cf, Color = color, Material = Enum.Material.Glass, Transparency = 0.15, Reflectance = 0.2 })
		part(model, { Size = Vector3.new(w * 0.45, h * 0.8, w * 0.45), CFrame = cf, Color = color:Lerp(Color3.new(1, 1, 1), 0.5), Material = Enum.Material.Neon, Transparency = 0.3 })
		part(model, { Size = Vector3.new(w * 0.72, w * 0.72, w * 0.72), CFrame = cf * CFrame.new(0, h / 2, 0) * CFrame.Angles(math.rad(45), 0, math.rad(45)), Color = color, Material = Enum.Material.Glass, Transparency = 0.15 })
	end
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 14
	light.Brightness = 1.5
	light.Parent = model:FindFirstChildWhichIsA("BasePart")
	return Vector3.new(5, 7, 5)
end

local function buildGift(model, base, color, ribbon)
	part(model, { Size = Vector3.new(6, 5, 6), CFrame = base * CFrame.new(0, 2.5, 0), Color = color })
	part(model, { Size = Vector3.new(6.6, 1.2, 6.6), CFrame = base * CFrame.new(0, 5.4, 0), Color = color:Lerp(Color3.new(1, 1, 1), 0.15) })
	for _, rot in ipairs({ 0, 90 }) do
		part(model, { Size = Vector3.new(1.1, 6.15, 6.7), CFrame = base * CFrame.new(0, 3, 0) * CFrame.Angles(0, math.rad(rot), 0), Color = ribbon })
	end
	for _, s in ipairs({ -1, 1 }) do
		part(model, { Shape = Enum.PartType.Ball, Size = Vector3.new(2.4, 1.6, 1.2), CFrame = base * CFrame.new(s * 1.05, 6.6, 0) * CFrame.Angles(0, 0, math.rad(s * -25)), Color = ribbon })
	end
	part(model, { Shape = Enum.PartType.Ball, Size = Vector3.new(1.1, 1.1, 1.1), CFrame = base * CFrame.new(0, 6.5, 0), Color = ribbon:Lerp(Color3.new(1, 1, 1), 0.3) })
	local sparkle = Instance.new("Sparkles")
	sparkle.SparkleColor = ribbon
	sparkle.Parent = model:FindFirstChildWhichIsA("BasePart")
	return Vector3.new(6.8, 7.4, 6.8)
end

local function pickType()
	local total = 0
	for _, t in ipairs(CFG.Types) do
		total += t.weight
	end
	local r = math.random() * total
	for _, t in ipairs(CFG.Types) do
		r -= t.weight
		if r <= 0 then
			return t
		end
	end
	return CFG.Types[1]
end

local function freeSpot(zone)
	local spots = MapBuilder.GetCoinSpots(zone.id)
	for _ = 1, 30 do
		local pos = spots[math.random(#spots)]
		local ok = true
		for model in pairs(breakables) do
			if model.Parent and (model:GetPivot().Position - pos).Magnitude < 14 then
				ok = false
				break
			end
		end
		if ok then
			return pos
		end
	end
	return nil
end

local function formatNumber(n)
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1 "):reverse()
	return (out:gsub("^ ", ""))
end

local spawnBreakable

local function setTarget(player, model)
	player:SetAttribute("BreakTarget", model and model.Name or nil)
end

local function onClick(player, model)
	local info = breakables[model]
	if not info then
		return
	end
	local data = DataService.Get(player)
	if not data then
		return
	end
	if not data.Zones[info.zone.id] then
		Remotes.Notify:FireClient(player, "🔒 Debloque d'abord la zone " .. info.zone.name .. " !", "danger")
		return
	end
	if player:GetAttribute("BreakTarget") == model.Name then
		setTarget(player, nil) -- deuxieme clic : les pets reviennent
		return
	end
	setTarget(player, model)
	if #PetService.GetEquippedPets(player) == 0 then
		Remotes.Notify:FireClient(player, "Equipe des pets pour casser beaucoup plus vite !", "info")
	end
end

local function updateBar(info)
	local ratio = math.clamp(info.hp / info.maxHp, 0, 1)
	info.bar.Size = UDim2.fromScale(ratio, 1)
	info.label.Text = formatNumber(math.max(info.hp, 0)) .. " PV"
end

local function shake(model, info)
	if info.shaking then
		return
	end
	info.shaking = true
	local pivot = info.pivot
	task.spawn(function()
		for i = 1, 3 do
			if not model.Parent then
				return
			end
			local a = (i % 2 == 0) and 6 or -6
			model:PivotTo(pivot * CFrame.Angles(0, 0, math.rad(a)) * CFrame.new(0, 0.25, 0))
			task.wait(0.05)
		end
		if model.Parent then
			model:PivotTo(pivot)
		end
		info.shaking = false
	end)
end

local function breakIt(model, info)
	breakables[model] = nil
	local pos = model:GetPivot().Position + Vector3.new(0, 3, 0)
	local total = 0
	for _, dmg in pairs(info.hits) do
		total += dmg
	end
	for player, dmg in pairs(info.hits) do
		if player.Parent == Players and DataService.Get(player) then
			local share = total > 0 and dmg / total or 1
			local power = PetService.GetPower(player)
			local amount = math.max(1, math.floor(info.reward * share * (1 + power * 0.08) + 0.5))
			PetService.AddCoins(player, amount)
			PetService.Sync(player)
			Remotes.FX:FireAllClients("Collect", { position = pos, userId = player.UserId, amount = amount, chest = info.type.id == "Gift" })
			if info.type.id == "Gift" then
				Remotes.Notify:FireClient(player, "🎁 Cadeau geant casse : +" .. formatNumber(amount) .. " coins !", "gold")
			end
		end
	end
	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("BreakTarget") == model.Name then
			setTarget(player, nil)
		end
	end
	-- petit eclatement : les morceaux s'envolent et disparaissent
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			local dir = (p.Position - pos)
			dir = (dir.Magnitude > 0.1 and dir.Unit or Vector3.yAxis) * 6 + Vector3.new(0, 5, 0)
			TweenService:Create(p, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Position = p.Position + dir,
				Transparency = 1,
				Size = p.Size * 0.4,
			}):Play()
		elseif p:IsA("BillboardGui") then
			p.Enabled = false
		end
	end
	task.delay(0.5, function()
		model:Destroy()
	end)
	task.delay(math.random(CFG.Respawn[1], CFG.Respawn[2]), function()
		spawnBreakable(info.zone)
	end)
end

function spawnBreakable(zone)
	local pos = freeSpot(zone)
	if not pos then
		return
	end
	local kind = pickType()
	local mult = CFG.ZoneMult[zone.id] or 1
	local tint = ZONE_TINT[zone.id] or ZONE_TINT.Village
	counter += 1
	local model = Instance.new("Model")
	model.Name = "Breakable" .. counter
	local ground = Vector3.new(pos.X, pos.Y - 2.2, pos.Z)
	local base = CFrame.new(ground) * CFrame.Angles(0, math.random() * math.pi * 2, 0)
	local size
	if kind.id == "Piggy" then
		size = buildPiggy(model, base)
	elseif kind.id == "Crystal" then
		size = buildCrystal(model, base, tint.crystal)
	else
		size = buildGift(model, base, tint.gift, tint.ribbon)
	end
	-- zone cliquable invisible
	local hitbox = part(model, {
		Name = "Hitbox",
		Size = size,
		CFrame = CFrame.new(ground + Vector3.new(0, size.Y / 2, 0)),
		Transparency = 1,
		CanQuery = true,
	})
	model.PrimaryPart = hitbox
	local click = Instance.new("ClickDetector")
	click.MaxActivationDistance = 70
	click.CursorIcon = ""
	click.Parent = hitbox
	-- barre de vie
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(150, 46)
	gui.StudsOffsetWorldSpace = Vector3.new(0, size.Y / 2 + 2, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 80
	gui.Parent = hitbox
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0, 20)
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.TextColor3 = Color3.new(1, 1, 1)
	title.TextStrokeTransparency = 0.2
	title.Text = kind.name .. "  💰 " .. formatNumber(kind.reward * mult)
	title.Parent = gui
	local back = Instance.new("Frame")
	back.Position = UDim2.fromOffset(0, 24)
	back.Size = UDim2.new(1, 0, 0, 18)
	back.BackgroundColor3 = Color3.fromRGB(35, 28, 50)
	back.Parent = gui
	Instance.new("UICorner", back).CornerRadius = UDim.new(1, 0)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(1, 1, 1)
	stroke.Thickness = 2
	stroke.Parent = back
	local bar = Instance.new("Frame")
	bar.Size = UDim2.fromScale(1, 1)
	bar.BackgroundColor3 = Color3.fromRGB(90, 230, 110)
	bar.Parent = back
	Instance.new("UICorner", bar).CornerRadius = UDim.new(1, 0)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.3
	label.ZIndex = 2
	label.Parent = back
	model:SetAttribute("Zone", zone.id)
	model.Parent = folder
	local info = {
		zone = zone,
		type = kind,
		hp = kind.hp * mult,
		maxHp = kind.hp * mult,
		reward = kind.reward * mult,
		hits = {},
		bar = bar,
		label = label,
		pivot = model:GetPivot(),
	}
	breakables[model] = info
	updateBar(info)
	click.MouseClick:Connect(function(player)
		onClick(player, model)
	end)
end

local function damageLoop()
	while true do
		task.wait(CFG.Tick)
		for _, player in ipairs(Players:GetPlayers()) do
			local name = player:GetAttribute("BreakTarget")
			if name then
				local model = folder:FindFirstChild(name)
				local info = model and breakables[model]
				local char = player.Character
				local hrp = char and char:FindFirstChild("HumanoidRootPart")
				if not info or not hrp or (hrp.Position - model:GetPivot().Position).Magnitude > CFG.MaxDistance then
					setTarget(player, nil)
				else
					local dmg = CFG.PlayerDamage
					for _, pet in ipairs(PetService.GetEquippedPets(player)) do
						local def = Config.PetById[pet.id]
						local rarity = def and Config.RarityById[def.rarity]
						local mult = (Config.Evolutions[pet.evo or 1] or Config.Evolutions[1]).mult
						dmg += CFG.PetBaseDamage + (rarity and rarity.power or 1) * mult * CFG.PetPowerDamage
					end
					info.hp -= dmg
					info.hits[player] = (info.hits[player] or 0) + dmg
					if info.hp <= 0 then
						breakIt(model, info)
					else
						updateBar(info)
						shake(model, info)
					end
				end
			end
		end
	end
end

function BreakableService.Init()
	folder = workspace:FindFirstChild("Breakables") or Instance.new("Folder")
	folder.Name = "Breakables"
	folder.Parent = workspace
	for _, zone in ipairs(Config.Zones) do
		for _ = 1, CFG.PerZone do
			spawnBreakable(zone)
		end
	end
	Players.PlayerRemoving:Connect(function(player)
		for _, info in pairs(breakables) do
			info.hits[player] = nil
		end
	end)
	task.spawn(damageLoop)
	local function tip(player)
		task.delay(10, function()
			if player.Parent == Players then
				Remotes.Notify:FireClient(player, "💥 Clique sur les tirelires, cristaux et cadeaux : tes pets les cassent pour des coins !", "gold")
			end
		end)
	end
	for _, player in ipairs(Players:GetPlayers()) do
		tip(player)
	end
	Players.PlayerAdded:Connect(tip)
end

return BreakableService
