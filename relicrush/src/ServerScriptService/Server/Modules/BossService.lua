-- Boss de chaque monde : golem anime dans l'arene, PV qui s'adaptent au nombre de joueurs,
-- onde de choc qui repousse (sans degats), recompenses partagees selon les degats infliges,
-- chance d'obtenir la relique du boss. Combats multijoueurs.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local F = require(ReplicatedStorage.Shared.Formulas)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local DataService = require(script.Parent.DataService)
local Targets = require(script.Parent.Targets)
local WorldBuilder = require(script.Parent.WorldBuilder)

local BossService = {}

local state = {} -- [worldId] = { model, alive, respawnAt }

local function playersInWorld(worldId)
	local list = {}
	for _, p in ipairs(Players:GetPlayers()) do
		local hrp = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		local w = hrp and WorldBuilder.WorldAt(hrp.Position)
		if w and w.id == worldId then
			table.insert(list, p)
		end
	end
	return list
end

local function part(model, props)
	local x = Instance.new("Part")
	x.Anchored = true
	x.CanCollide = false
	x.CanQuery = false
	x.CanTouch = false
	for k, v in pairs(props) do
		x[k] = v
	end
	x.Parent = model
	return x
end

-- Golem (comme l'icone BOSS) : corps de pierre, casque dore a cornes, yeux et cristaux lumineux
local function buildGolem(world, pos)
	local relic = Config.RelicById
	local glow = Color3.fromRGB(200, 90, 255)
	for _, r in ipairs(Config.Relics) do
		if r.boss and r.world == world.id then
			glow = r.c2
		end
	end
	local stone = world.id == "Frozen" and Color3.fromRGB(190, 215, 240) or (world.id == "Lava" and Color3.fromRGB(70, 55, 55) or (world.id == "Celestial" and Color3.fromRGB(235, 230, 245) or Color3.fromRGB(120, 112, 135)))
	local gold = Color3.fromRGB(255, 195, 60)
	local model = Instance.new("Model")
	model.Name = "Boss_" .. world.id
	local base = CFrame.new(pos)
	local S = 1.6
	local function rock(size, cf, color, mat)
		return part(model, { Size = size * S, CFrame = base * CFrame.new(cf.Position * S) * cf.Rotation, Color = color or stone, Material = mat or Enum.Material.Slate })
	end
	rock(Vector3.new(9, 8, 6), CFrame.new(0, 9, 0))
	rock(Vector3.new(7, 4, 5), CFrame.new(0, 4, 0))
	rock(Vector3.new(6, 5, 5.5), CFrame.new(0, 15, -0.5))
	rock(Vector3.new(7.2, 1.6, 6.2), CFrame.new(0, 17.4, -0.5), gold, Enum.Material.Metal)
	rock(Vector3.new(2.4, 1, 0.5), CFrame.new(0, 18.6, -3.4), gold, Enum.Material.Metal)
	for _, s in ipairs({ -1, 1 }) do
		rock(Vector3.new(1.4, 0.7, 0.3), CFrame.new(s * 1.3, 15.4, -3.3), glow, Enum.Material.Neon)
		rock(Vector3.new(1.2, 4, 1.2), CFrame.new(s * 4.2, 19.5, -0.5) * CFrame.Angles(0, 0, math.rad(-s * 35)), gold, Enum.Material.Metal)
		rock(Vector3.new(4, 4, 4), CFrame.new(s * 6.6, 11, 0), stone)
		rock(Vector3.new(3.2, 6, 3.2), CFrame.new(s * 7.2, 6, -0.5))
		rock(Vector3.new(3.6, 3, 3.6), CFrame.new(s * 7.2, 2.4, -0.8))
		rock(Vector3.new(3, 4, 3), CFrame.new(s * 2.6, 1.6, 0))
		for k = 1, 2 do
			rock(Vector3.new(1.2, 3, 1.2), CFrame.new(s * (5 + k), 12.5 + k, 1.5) * CFrame.Angles(0.3, 0, -s * 0.4), glow, Enum.Material.Neon)
		end
	end
	rock(Vector3.new(4, 1.2, 0.4), CFrame.new(0, 9, -3.1), gold, Enum.Material.Metal)
	rock(Vector3.new(1.4, 1.4, 0.4), CFrame.new(0, 9, -3.3) * CFrame.Angles(0, 0, math.rad(45)), glow, Enum.Material.Neon)
	local light = Instance.new("PointLight")
	light.Color = glow
	light.Range = 30
	light.Brightness = 2
	light.Parent = model:GetChildren()[1]
	local hit = part(model, { Name = "Hitbox", Size = Vector3.new(18, 30, 14), CFrame = base * CFrame.new(0, 15, 0), Transparency = 1, CanQuery = true })
	model.PrimaryPart = hit
	return model
end

local function spawnBoss(world)
	local pos = WorldBuilder.Arena(world.id)
	if not pos then
		return
	end
	local def = Config.Boss[world.id]
	local n = math.max(1, #playersInWorld(world.id))
	local model = buildGolem(world, pos)
	model:SetAttribute("Label", def.name)
	local st = state[world.id]
	st.model = model
	st.alive = true
	st.base = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			st.base[d] = d.CFrame
		end
	end
	Targets.Register(model, {
		kind = "boss",
		world = world.id,
		maxHp = math.floor(def.hp * world.mult * (1 + (n - 1) * Config.BossHpPerPlayer)),
		onHit = function(m, info, player)
			local data = DataService.Get(player)
			if data and not info.fought then
				info.fought = {}
			end
			if data and not info.fought[player] then
				info.fought[player] = true
				data.Stats.BossFights += 1
			end
		end,
		onDeath = function(m, info)
			st.alive = false
			st.model = nil
			st.respawnAt = os.time() + Config.BossRespawn
			local total = 0
			for _, d in pairs(info.hits) do
				total += d
			end
			for player, dmg in pairs(info.hits) do
				local data = DataService.Get(player)
				if data and player.Parent == Players then
					local share = dmg / math.max(total, 1)
					local coins = math.floor(def.coins * world.mult * math.max(share, 0.1) * F.CoinMult(data) * (1 + #Players:GetPlayers() * 0.1))
					DataService.AddCoins(player, coins)
					local relic
					if share >= 0.05 then
						data.Stats.BossWins += 1
						if math.random() < Config.BossRelicChance then
							for _, r in ipairs(Config.Relics) do
								if r.boss and r.world == world.id then
									local uid, first = DataService.GiveRelic(player, r.id)
									if uid then
										relic = r.id
										Remotes.Notify:FireAllClients(player.DisplayName .. " a obtenu " .. r.name .. " sur le boss !", "gold")
									end
								end
							end
						end
					end
					Remotes.FX:FireClient(player, "BossReward", { boss = def.name, coins = coins, share = share, relic = relic })
					DataService.Sync(player)
				end
			end
			Remotes.FX:FireAllClients("BossDown", { world = world.id, position = m.PrimaryPart.Position })
			for _, d in ipairs(m:GetDescendants()) do
				if d:IsA("BasePart") then
					d.Anchored = false
					d.CanCollide = true
					d.AssemblyLinearVelocity = Vector3.new(math.random(-30, 30), math.random(20, 50), math.random(-30, 30))
				end
			end
			task.delay(4, function()
				m:Destroy()
			end)
		end,
	})
	Remotes.Notify:FireAllClients(def.name .. " est apparu dans " .. world.name .. " !", "gold")
end

-- Animation : respiration, regard vers le joueur le plus proche, onde de choc
local function animate(dt)
	local t = os.clock()
	for worldId, st in pairs(state) do
		local m = st.model
		if st.alive and m and m.Parent and m.PrimaryPart then
			local center = st.base[m.PrimaryPart].Position
			local nearest, nd
			for _, p in ipairs(Players:GetPlayers()) do
				local hrp = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
				if hrp then
					local d = (hrp.Position - center).Magnitude
					if d < 80 and (not nd or d < nd) then
						nearest, nd = hrp, d
					end
				end
			end
			if nearest then
				local dir = (nearest.Position - center) * Vector3.new(1, 0, 1)
				if dir.Magnitude > 1 then
					local target = math.atan2(-dir.X, -dir.Z)
					st.yaw = st.yaw or 0
					local diff = (target - st.yaw + math.pi) % (2 * math.pi) - math.pi
					st.yaw += diff * math.min(dt * 2, 1)
				end
			end
			local bob = math.sin(t * 2) * 0.6
			local pivot = CFrame.new(center.X, center.Y - 15 + bob, center.Z) * CFrame.Angles(0, st.yaw or 0, 0)
			local origin = CFrame.new(center.X, center.Y - 15, center.Z)
			local parts, cfs = {}, {}
			for p, cf in pairs(st.base) do
				if p.Parent then
					table.insert(parts, p)
					table.insert(cfs, pivot * origin:ToObjectSpace(cf))
				end
			end
			workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
		end
	end
end

local function shockwaves()
	while true do
		task.wait(Config.BossShockwave.Interval)
		for worldId, st in pairs(state) do
			local m = st.model
			if st.alive and m and m.PrimaryPart then
				local pos = WorldBuilder.Arena(worldId)
				local pushed = false
				for _, p in ipairs(Players:GetPlayers()) do
					local hrp = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
					if hrp then
						local d = hrp.Position - pos
						if d.Magnitude < Config.BossShockwave.Radius then
							local dir = Vector3.new(d.X, 0, d.Z)
							dir = dir.Magnitude > 0.1 and dir.Unit or Vector3.new(1, 0, 0)
							hrp.AssemblyLinearVelocity = dir * Config.BossShockwave.Push + Vector3.new(0, 45, 0)
							pushed = true
						end
					end
				end
				if pushed then
					Remotes.FX:FireAllClients("Shockwave", { position = pos, radius = Config.BossShockwave.Radius })
				end
			end
		end
	end
end

function BossService.Status()
	local out = {}
	for _, w in ipairs(Config.Worlds) do
		local st = state[w.id]
		local info = st.model and Targets.Get(st.model)
		out[w.id] = {
			alive = st.alive,
			hp = info and info.hp or 0,
			maxHp = info and info.maxHp or 0,
			respawnAt = st.respawnAt,
			name = Config.Boss[w.id].name,
			model = st.model,
		}
	end
	return out
end

function BossService.Init()
	for _, w in ipairs(Config.Worlds) do
		state[w.id] = { alive = false, respawnAt = os.time() + 5 }
	end
	RunService.Heartbeat:Connect(animate)
	task.spawn(shockwaves)
	task.spawn(function()
		while true do
			task.wait(1)
			for _, w in ipairs(Config.Worlds) do
				local st = state[w.id]
				if not st.alive and st.respawnAt and os.time() >= st.respawnAt then
					st.respawnAt = nil
					local ok, err = pcall(spawnBoss, w)
					if not ok then
						warn("[RelicRush] Boss " .. w.id .. " : " .. tostring(err))
						st.respawnAt = os.time() + 30
					end
				end
			end
			Remotes.Boss:FireAllClients(BossService.Status(), os.time())
		end
	end)
end

return BossService
