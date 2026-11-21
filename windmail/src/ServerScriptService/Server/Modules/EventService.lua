-- Evenements aleatoires du serveur : Vent dore (x2), Ballon egare (chasse en vol),
-- Grande Tournee (objectif commun). Annonces a tous les joueurs.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Progress = require(ReplicatedStorage.Shared.Progress)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local DataService = require(script.Parent.DataService)
local StampService = require(script.Parent.StampService)
local ParcelService = require(script.Parent.ParcelService)

local EventService = {}

local current -- { def, endsAt, ... }

local function defById(id)
	for _, e in ipairs(Config.Events.List) do
		if e.id == id then
			return e
		end
	end
end

local function broadcast(kind, extra)
	local payload = extra or {}
	if current then
		payload.id = current.def.id
		payload.name = current.def.name
		payload.desc = current.def.desc
		payload.color = current.def.color
		payload.endsAt = current.endsAt
	end
	Remotes.Event:FireAllClients(kind, payload)
end

local function reward(player, coins, xp)
	DataService.AddCoins(player, coins)
	local up = DataService.AddXP(player, xp)
	if up then
		Remotes.FX:FireClient(player, "RankUp", { rank = up, title = Progress.Title(up) })
	end
	DataService.Sync(player)
end

local function scaled(player, base)
	local data = DataService.Get(player)
	local rank = data and Progress.RankFromXP(data.XP) or 1
	return math.floor(base * (1 + rank * 0.25))
end

-- Ballon egare -----------------------------------------------------------------------------------
local function runBalloon()
	local points = {}
	for _, z in ipairs(Config.Zones) do
		table.insert(points, z.center + Vector3.new(math.random(-60, 60), math.random(90, 140), math.random(-60, 60)))
	end
	for i = #points, 2, -1 do
		local j = math.random(i)
		points[i], points[j] = points[j], points[i]
	end
	local model = Instance.new("Model")
	model.Name = "LostBalloon"
	local env = Instance.new("Part")
	env.Name = "Envelope"
	env.Shape = Enum.PartType.Ball
	env.Size = Vector3.new(12, 12, 12)
	env.Color = Color3.fromRGB(230, 80, 100)
	env.Material = Enum.Material.Fabric
	env.Anchored = true
	env.CanCollide = false
	env.CFrame = CFrame.new(points[1])
	env.Parent = model
	local bag = Instance.new("Part")
	bag.Name = "Mailbag"
	bag.Size = Vector3.new(3, 3, 3)
	bag.Color = Color3.fromRGB(150, 110, 70)
	bag.Material = Enum.Material.Fabric
	bag.Anchored = true
	bag.CanCollide = false
	bag.CFrame = env.CFrame * CFrame.new(0, -10, 0)
	bag.Parent = model
	local beam = Instance.new("Part")
	beam.Size = Vector3.new(1.2, 300, 1.2)
	beam.Material = Enum.Material.Neon
	beam.Color = Color3.fromRGB(255, 150, 170)
	beam.Transparency = 0.5
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanTouch = false
	beam.CFrame = env.CFrame * CFrame.new(0, 150, 0)
	beam.Parent = model
	local hitbox = Instance.new("Part")
	hitbox.Name = "Hitbox"
	hitbox.Size = Vector3.new(16, 26, 16)
	hitbox.Transparency = 1
	hitbox.Anchored = true
	hitbox.CanCollide = false
	hitbox.CFrame = env.CFrame * CFrame.new(0, -4, 0)
	hitbox.Parent = model
	model.PrimaryPart = hitbox
	model.Parent = workspace
	current.balloon = model
	broadcast("balloon", { target = model })
	local caught = false
	hitbox.Touched:Connect(function(hit)
		if caught then
			return
		end
		local player = Players:GetPlayerFromCharacter(hit.Parent)
		if not player or not DataService.Get(player) then
			return
		end
		caught = true
		StampService.Give(player, "Ballon")
		reward(player, scaled(player, 600), 200)
		Remotes.Notify:FireAllClients(player.DisplayName .. " a attrape le ballon egare !", "gold")
		Remotes.FX:FireAllClients("Confetti", { position = hitbox.Position, userId = player.UserId })
		current.endsAt = workspace:GetServerTimeNow()
	end)
	-- trajet lent d'une ile a l'autre
	task.spawn(function()
		local i = 1
		while not caught and current and workspace:GetServerTimeNow() < current.endsAt do
			i = (i % #points) + 1
			local target = points[i]
			local dist = (target - env.Position).Magnitude
			local t = dist / 14
			local info = TweenInfo.new(t, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
			for _, p in ipairs(model:GetChildren()) do
				local offset = p.CFrame.Position - env.Position
				TweenService:Create(p, info, { CFrame = CFrame.new(target + offset) }):Play()
			end
			local t0 = os.clock()
			while os.clock() - t0 < t and not caught and workspace:GetServerTimeNow() < current.endsAt do
				task.wait(0.5)
			end
		end
	end)
end

-- Grande Tournee -----------------------------------------------------------------------------------
local function onDeliveryTournee(player)
	if not (current and current.def.id == "Tournee") then
		return
	end
	current.count += 1
	current.contributors[player] = true
	broadcast("progress", { count = current.count, goal = current.goal })
	if current.count >= current.goal and not current.done then
		current.done = true
		for p in pairs(current.contributors) do
			if p.Parent == Players then
				reward(p, scaled(p, 500), 250)
				if math.random() < 0.35 then
					StampService.Give(p, "Tournee")
				end
			end
		end
		Remotes.Notify:FireAllClients("Grande Tournee reussie ! Tous les participants sont recompenses.", "gold")
		current.endsAt = workspace:GetServerTimeNow()
	end
end

local function start(def)
	current = { def = def, endsAt = workspace:GetServerTimeNow() + def.duration }
	if def.id == "VentDore" then
		ParcelService.CoinMultiplier = function()
			return 2
		end
		broadcast("start")
	elseif def.id == "Ballon" then
		broadcast("start")
		runBalloon()
	elseif def.id == "Tournee" then
		current.count = 0
		current.goal = math.max(def.goalMin, def.goalPerPlayer * #Players:GetPlayers())
		current.contributors = {}
		broadcast("start", { count = 0, goal = current.goal })
	end
	while workspace:GetServerTimeNow() < current.endsAt do
		task.wait(1)
	end
	ParcelService.CoinMultiplier = function()
		return 1
	end
	if current.balloon then
		current.balloon:Destroy()
	end
	broadcast("end")
	current = nil
end

function EventService.Current()
	return current
end

function EventService.Init()
	table.insert(ParcelService.EventHooks, onDeliveryTournee)
	Players.PlayerAdded:Connect(function(player)
		task.wait(4)
		if current then
			Remotes.Event:FireClient(player, "start", {
				id = current.def.id, name = current.def.name, desc = current.def.desc, color = current.def.color,
				endsAt = current.endsAt, count = current.count, goal = current.goal, target = current.balloon,
			})
		end
	end)
	task.spawn(function()
		while true do
			task.wait(math.random(Config.Events.Interval[1], Config.Events.Interval[2]))
			if #Players:GetPlayers() > 0 then
				local list = Config.Events.List
				local ok, err = pcall(start, list[math.random(#list)])
				if not ok then
					warn("[Windmail] Evenement : " .. tostring(err))
					current = nil
				end
			end
		end
	end)
end

-- Pour tester dans Studio : require(...EventService).Force("Ballon")
function EventService.Force(id)
	local def = defById(id)
	if def and not current then
		task.spawn(start, def)
	end
end

return EventService
