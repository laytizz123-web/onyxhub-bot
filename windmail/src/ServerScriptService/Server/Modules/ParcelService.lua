-- Coeur du jeu : missions de livraison.
-- Guichet -> colis attribues (destinations dans les zones debloquees) -> vol -> livraison a la
-- boite aux lettres -> note S/A/B/C selon le temps, integrite, convoi, evenement -> pieces + XP.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Progress = require(ReplicatedStorage.Shared.Progress)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local DataService = require(script.Parent.DataService)
local StampService = require(script.Parent.StampService)

local ParcelService = {}
ParcelService.EventHooks = {} -- fonctions(player) appelees a chaque livraison (evenements)
ParcelService.CoinMultiplier = function()
	return 1
end

local D = Config.Delivery
local carrying = {} -- [player] = { parcels }
local nextId = 0

local function capacity(data)
	return Config.Satchels[data.Satchel].capacity
end

local function zoneUnlocked(rank, zoneId)
	local z = Config.ZoneById[zoneId]
	return z and rank >= z.rank
end

-- Colis sur le dos (visibles par tous)
local function refreshVisual(player)
	local char = player.Character
	local torso = char and (char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso"))
	if not torso then
		return
	end
	local old = char:FindFirstChild("Satchel")
	if old then
		old:Destroy()
	end
	local list = carrying[player] or {}
	player:SetAttribute("Heavy", false)
	if #list == 0 then
		return
	end
	local model = Instance.new("Model")
	model.Name = "Satchel"
	local y = 0
	for i, p in ipairs(list) do
		local def = Config.ParcelById[p.type]
		local s = def.size * 0.7
		local box = Instance.new("Part")
		box.Name = "Parcel"
		box.Size = s
		box.Color = def.color
		box.Material = Enum.Material.Fabric
		pcall(function()
			box.Material = def.id == "Lettre" and Enum.Material.Fabric or Enum.Material.Cardboard
		end)
		box.CanCollide = false
		box.CanQuery = false
		box.CanTouch = false
		box.Massless = true
		box.CFrame = torso.CFrame * CFrame.new(0, -0.2 + y + s.Y / 2, torso.Size.Z / 2 + s.Z / 2 + 0.05)
		y += s.Y + 0.05
		local tape = Instance.new("Part")
		tape.Size = Vector3.new(s.X + 0.02, s.Y + 0.02, 0.25)
		tape.Color = Color3.fromRGB(215, 190, 140)
		tape.Material = Enum.Material.Fabric
		tape.CanCollide = false
		tape.CanQuery = false
		tape.Massless = true
		tape.CFrame = box.CFrame
		tape.Parent = model
		local w2 = Instance.new("WeldConstraint")
		w2.Part0 = box
		w2.Part1 = tape
		w2.Parent = tape
		local w = Instance.new("WeldConstraint")
		w.Part0 = torso
		w.Part1 = box
		w.Parent = box
		box.Parent = model
		if def.heavy then
			player:SetAttribute("Heavy", true)
		end
	end
	model.Parent = char
end

local function sendList(player)
	local out = {}
	for _, p in ipairs(carrying[player] or {}) do
		table.insert(out, {
			id = p.id,
			type = p.type,
			mailbox = p.mailbox,
			owner = p.mailbox:GetAttribute("Owner"),
			zone = p.mailbox:GetAttribute("Zone"),
			par = p.par,
			start = p.start,
			deadline = p.deadline,
			integrity = p.integrity,
			serverNow = workspace:GetServerTimeNow(),
		})
	end
	Remotes.Parcels:FireClient(player, out)
end

local function pickType(rank, dist, hasHeavy)
	local pool, total = {}, 0
	for _, t in ipairs(Config.Parcels) do
		local ok = rank >= t.rank
		if t.express and dist < 90 then
			ok = false
		end
		if t.heavy and hasHeavy then
			ok = false
		end
		if ok then
			table.insert(pool, t)
			total += t.weight
		end
	end
	local r = math.random() * total
	for _, t in ipairs(pool) do
		r -= t.weight
		if r <= 0 then
			return t
		end
	end
	return pool[1]
end

local function takeParcels(player, counter)
	local data = DataService.Get(player)
	if not data then
		return
	end
	local list = carrying[player] or {}
	carrying[player] = list
	local free = capacity(data) - #list
	if free <= 0 then
		Remotes.Notify:FireClient(player, "Ta sacoche est pleine ! Livre tes colis (ou ameliore ta sacoche).", "info")
		return
	end
	local rank = Progress.RankFromXP(data.XP)
	local origin = counter.Position
	local local_, far = {}, {}
	local here
	for _, z in ipairs(Config.Zones) do
		if (Vector3.new(origin.X, 0, origin.Z) - z.center).Magnitude < 160 then
			here = z.id
		end
	end
	local taken = {}
	for _, p in ipairs(list) do
		taken[p.mailbox] = true
	end
	for _, m in ipairs(CollectionService:GetTagged("Mailbox")) do
		local zone = m:GetAttribute("Zone")
		if m.PrimaryPart and zoneUnlocked(rank, zone) and not taken[m] and (m.PrimaryPart.Position - origin).Magnitude > 30 then
			if zone == here then
				table.insert(local_, m)
			else
				table.insert(far, m)
			end
		end
	end
	local hasHeavy = false
	for _, p in ipairs(list) do
		if Config.ParcelById[p.type].heavy then
			hasHeavy = true
		end
	end
	local given = 0
	for _ = 1, free do
		local pool = (#far > 0 and (math.random() < 0.4 or #local_ == 0)) and far or local_
		if #pool == 0 then
			break
		end
		local m = table.remove(pool, math.random(#pool))
		local dist = (m.PrimaryPart.Position - origin).Magnitude
		local t = pickType(rank, dist, hasHeavy)
		hasHeavy = hasHeavy or t.heavy == true
		nextId += 1
		local par = dist / D.ParSpeed + D.ParBonus
		if t.heavy then
			par *= 1.2
		end
		local now = workspace:GetServerTimeNow()
		table.insert(list, {
			id = nextId,
			type = t.id,
			mailbox = m,
			origin = origin,
			dist = dist,
			start = now,
			par = par,
			deadline = t.express and (now + par * D.ExpressFactor) or nil,
			integrity = 1,
		})
		given += 1
	end
	if given == 0 then
		Remotes.Notify:FireClient(player, "Aucune destination disponible pour l'instant.", "info")
		return
	end
	Remotes.FX:FireClient(player, "Pickup", { count = given })
	refreshVisual(player)
	sendList(player)
end

local function gradeFor(ratio)
	for _, g in ipairs(D.Grades) do
		if ratio <= g.max then
			return g
		end
	end
	return D.Grades[#D.Grades]
end

local function deliver(player, mailbox)
	local data = DataService.Get(player)
	local list = carrying[player]
	if not (data and list) then
		return
	end
	local index
	for i, p in ipairs(list) do
		if p.mailbox == mailbox then
			index = i
			break
		end
	end
	if not index then
		if #list > 0 then
			Remotes.Notify:FireClient(player, "Ce n'est pas la bonne boite aux lettres ! Suis les fleches.", "info")
		end
		return
	end
	local p = table.remove(list, index)
	local def = Config.ParcelById[p.type]
	local now = workspace:GetServerTimeNow()
	local elapsed = now - p.start
	local grade = gradeFor(elapsed / p.par)
	local bonuses = Progress.SetBonuses(data.Stamps)
	-- convoi : autres facteurs proches de la boite aux lettres
	local helpers = {}
	local mpos = mailbox.PrimaryPart.Position
	for _, other in ipairs(Players:GetPlayers()) do
		local ch = other.Character
		local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
		if other ~= player and hrp and (hrp.Position - mpos).Magnitude <= D.ConvoyRadius then
			table.insert(helpers, other)
		end
	end
	local base = D.BaseCoins + p.dist * D.CoinsPerStud
	local convoy = #helpers > 0 and (1 + D.ConvoyBonus) or 1
	local eventMult = ParcelService.CoinMultiplier()
	local coins = math.floor(base * def.pay * grade.mult * p.integrity * convoy * eventMult * (1 + bonuses.coin) + 0.5)
	local xp = math.floor(coins * D.XPPerCoin * (1 + bonuses.xp) + 0.5)
	DataService.AddCoins(player, coins)
	local newRank = DataService.AddXP(player, xp)
	data.Deliveries += 1
	data.Grades[grade.grade] = (data.Grades[grade.grade] or 0) + 1
	local stamp
	if def.mystery then
		stamp = StampService.RollMystery()
		StampService.Give(player, stamp)
	end
	for _, h in ipairs(helpers) do
		local share = math.max(1, math.floor(coins * D.ConvoyAssist))
		DataService.AddCoins(h, share)
		local up = DataService.AddXP(h, math.floor(share * D.XPPerCoin))
		Remotes.Notify:FireClient(h, "Convoi avec " .. player.DisplayName .. " : +" .. share .. " pieces", "good")
		if up then
			Remotes.FX:FireClient(h, "RankUp", { rank = up, title = Progress.Title(up) })
		end
		DataService.Sync(h)
	end
	Remotes.FX:FireClient(player, "Delivered", {
		parcel = def.name,
		owner = mailbox:GetAttribute("Owner"),
		grade = grade.grade,
		gradeColor = grade.color,
		coins = coins,
		xp = xp,
		time = elapsed,
		par = p.par,
		integrity = p.integrity,
		convoy = #helpers,
		event = eventMult > 1,
		stamp = stamp,
		position = mpos,
	})
	Remotes.FX:FireAllClients("Confetti", { position = mpos, userId = player.UserId })
	if newRank then
		Remotes.FX:FireClient(player, "RankUp", { rank = newRank, title = Progress.Title(newRank) })
		for _, z in ipairs(Config.Zones) do
			if z.rank == newRank then
				Remotes.Notify:FireClient(player, "Nouvelle zone de livraison : " .. z.name .. " !", "gold")
			end
		end
	end
	for _, hook in ipairs(ParcelService.EventHooks) do
		task.spawn(hook, player)
	end
	refreshVisual(player)
	sendList(player)
	DataService.Sync(player)
end

-- Sauvetage en mer : retour au quai le plus proche
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
rayParams.IgnoreWater = false

local function inWater(pos)
	rayParams.FilterDescendantsInstances = { workspace.Terrain }
	local hit = workspace:Raycast(pos + Vector3.new(0, 3, 0), Vector3.new(0, -6, 0), rayParams)
	return hit and hit.Material == Enum.Material.Water
end

local function rescue(player, hrp)
	local best, bestD
	for _, d in ipairs(CollectionService:GetTagged("Dock")) do
		local dist = (d.Position - hrp.Position).Magnitude
		if not bestD or dist < bestD then
			best, bestD = d, dist
		end
	end
	if best then
		hrp.AssemblyLinearVelocity = Vector3.zero
		hrp.CFrame = best.CFrame + Vector3.new(0, 3, 0)
	end
	local damaged = false
	for _, p in ipairs(carrying[player] or {}) do
		if Config.ParcelById[p.type].fragile then
			p.integrity = math.max(0.2, p.integrity - D.SplashDamage)
			damaged = true
		end
	end
	Remotes.FX:FireClient(player, "Splash", { damaged = damaged })
	if damaged then
		sendList(player)
	end
end

function ParcelService.Carrying(player)
	return carrying[player] or {}
end

function ParcelService.Init()
	local function hookCounter(counter)
		local prompt = counter:FindFirstChildOfClass("ProximityPrompt")
		if prompt then
			prompt.Triggered:Connect(function(player)
				takeParcels(player, counter)
			end)
		end
	end
	for _, c in ipairs(CollectionService:GetTagged("PostCounter")) do
		hookCounter(c)
	end
	CollectionService:GetInstanceAddedSignal("PostCounter"):Connect(hookCounter)
	local function hookMailbox(m)
		local box = m.PrimaryPart
		local prompt = box and box:FindFirstChildOfClass("ProximityPrompt")
		if prompt then
			prompt.Triggered:Connect(function(player)
				deliver(player, m)
			end)
		end
	end
	for _, m in ipairs(CollectionService:GetTagged("Mailbox")) do
		hookMailbox(m)
	end
	CollectionService:GetInstanceAddedSignal("Mailbox"):Connect(hookMailbox)

	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			task.wait(0.5)
			refreshVisual(player)
		end)
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		player.CharacterAdded:Connect(function()
			task.wait(0.5)
			refreshVisual(player)
		end)
	end
	Players.PlayerRemoving:Connect(function(player)
		carrying[player] = nil
	end)

	-- chocs (colis fragiles) et noyade : suivi de la vitesse
	local lastSpeed = {}
	RunService.Heartbeat:Connect(function()
		for _, player in ipairs(Players:GetPlayers()) do
			local list = carrying[player]
			local ch = player.Character
			local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
			if hrp and list and #list > 0 then
				local speed = hrp.AssemblyLinearVelocity.Magnitude
				local prev = lastSpeed[player] or speed
				lastSpeed[player] = speed
				if prev - speed > D.ImpactSpeed and speed < 25 then
					local hit = false
					for _, p in ipairs(list) do
						if Config.ParcelById[p.type].fragile then
							p.integrity = math.max(0.2, p.integrity - D.ImpactDamage)
							hit = true
						end
					end
					if hit then
						Remotes.FX:FireClient(player, "Impact", {})
						sendList(player)
					end
				end
			end
		end
	end)
	task.spawn(function()
		while true do
			task.wait(0.5)
			local now = workspace:GetServerTimeNow()
			for _, player in ipairs(Players:GetPlayers()) do
				local ch = player.Character
				local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
				local hum = ch and ch:FindFirstChildOfClass("Humanoid")
				if hrp and hum and hum.Health > 0 and hrp.Position.Y < 3 and inWater(hrp.Position) then
					rescue(player, hrp)
				end
				-- colis express hors delai
				local list = carrying[player]
				if list then
					for i = #list, 1, -1 do
						local p = list[i]
						if p.deadline and now > p.deadline then
							table.remove(list, i)
							Remotes.Notify:FireClient(player, "Colis express en retard : il retourne a la poste.", "danger")
							refreshVisual(player)
							sendList(player)
						end
					end
				end
			end
		end
	end)
end

return ParcelService
