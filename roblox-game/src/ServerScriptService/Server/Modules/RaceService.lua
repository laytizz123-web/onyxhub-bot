-- Courses de pets : lobby, compte a rebours, simulation avec Speed / Stamina / Luck, recompenses.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local PetModel = require(ReplicatedStorage.Shared.PetModel)
local DataService = require(script.Parent.DataService)
local MapBuilder = require(script.Parent.MapBuilder)
local PetService = require(script.Parent.PetService)

local RaceService = {}

local state = { phase = "Idle", type = nil, racers = {}, endsAt = 0 }
local runnersFolder

local function broadcast(extra)
	local payload = { phase = state.phase, type = state.type and state.type.id or nil, endsAt = state.endsAt, serverTime = workspace:GetServerTimeNow(), racers = {} }
	for _, r in ipairs(state.racers) do
		table.insert(payload.racers, { name = r.name, petId = r.petId, evo = r.evo, progress = r.progress or 0, finished = r.finished, rank = r.rank, userId = r.player and r.player.UserId or 0 })
	end
	if extra then
		for k, v in pairs(extra) do
			payload[k] = v
		end
	end
	Remotes.RaceSync:FireAllClients(payload)
end

local function pathLength(points)
	local total = 0
	for i = 1, #points do
		total += (points[(i % #points) + 1] - points[i]).Magnitude
	end
	return total
end

local function pointAt(points, distance)
	local total = pathLength(points)
	distance = distance % total
	for i = 1, #points do
		local a = points[i]
		local b = points[(i % #points) + 1]
		local len = (b - a).Magnitude
		if distance <= len then
			return a:Lerp(b, distance / len), b
		end
		distance -= len
	end
	return points[1], points[2]
end

local function join(player, typeId, uid)
	local data = DataService.Get(player)
	if not data then
		return
	end
	uid = tonumber(uid)
	local pet
	for _, p in ipairs(data.Pets) do
		if p.uid == uid then
			pet = p
		end
	end
	if not pet then
		Remotes.Notify:FireClient(player, "Choisis un pet pour la course.", "danger")
		return
	end
	if state.phase == "Idle" then
		local raceType
		for _, t in ipairs(Config.Race.Types) do
			if t.id == typeId then
				raceType = t
			end
		end
		if not raceType then
			return
		end
		state.phase = "Lobby"
		state.type = raceType
		state.racers = {}
		state.endsAt = workspace:GetServerTimeNow() + Config.Race.LobbyTime
		Remotes.Notify:FireAllClients("🏁 " .. player.DisplayName .. " lance une course " .. raceType.icon .. " " .. raceType.name .. " ! Rejoins au stand des courses.", "good")
		task.delay(Config.Race.LobbyTime, RaceService.Start)
	elseif state.phase ~= "Lobby" then
		Remotes.Notify:FireClient(player, "Une course est en cours, attends la prochaine.", "info")
		return
	end
	for _, r in ipairs(state.racers) do
		if r.player == player then
			r.petId = pet.id
			r.evo = pet.evo
			broadcast()
			Remotes.Notify:FireClient(player, "Pet de course change : " .. PetModel.DisplayName(pet.id, pet.evo), "good")
			return
		end
	end
	if #state.racers >= Config.Race.MaxRacers then
		Remotes.Notify:FireClient(player, "La course est pleine !", "danger")
		return
	end
	table.insert(state.racers, { player = player, name = player.DisplayName, petId = pet.id, evo = pet.evo, progress = 0 })
	Remotes.Notify:FireClient(player, "✅ Inscrit avec " .. PetModel.DisplayName(pet.id, pet.evo), "good")
	broadcast()
end

local function fillWithAI()
	local i = 0
	while #state.racers < Config.Race.MaxRacers do
		i += 1
		local pet = Config.Pets[math.random(1, 9)]
		table.insert(state.racers, { player = nil, name = "🤖 " .. (Config.Race.AINames[i] or ("Bot " .. i)), petId = pet.id, evo = 1, progress = 0 })
	end
end

function RaceService.Start()
	if state.phase ~= "Lobby" then
		return
	end
	-- Retire les joueurs partis
	for i = #state.racers, 1, -1 do
		local r = state.racers[i]
		if r.player and r.player.Parent ~= Players then
			table.remove(state.racers, i)
		end
	end
	fillWithAI()
	local points = MapBuilder.GetRaceWaypoints()
	local total = pathLength(points) * state.type.laps
	state.phase = "Countdown"
	state.endsAt = workspace:GetServerTimeNow() + Config.Race.Countdown
	-- Modeles des coureurs
	for i, r in ipairs(state.racers) do
		local stats = PetModel.Stats(r.petId, r.evo)
		r.stats = stats
		r.progress = 0
		r.finished = false
		r.rank = nil
		r.lane = (i - 2.5) * 2.2
		local pos = pointAt(points, 0)
		r.model = PetModel.Build(r.petId, r.evo, CFrame.new(pos + Vector3.new(0, -0.9, r.lane)))
		r.model.Parent = runnersFolder
		local tag = Instance.new("BillboardGui")
		tag.Size = UDim2.fromOffset(140, 30)
		tag.StudsOffset = Vector3.new(0, 3, 0)
		tag.AlwaysOnTop = true
		local l = Instance.new("TextLabel")
		l.Size = UDim2.fromScale(1, 1)
		l.BackgroundTransparency = 1
		l.Text = r.name
		l.Font = Enum.Font.FredokaOne
		l.TextScaled = true
		l.TextColor3 = r.player and Config.Colors.Gold or Color3.new(1, 1, 1)
		l.TextStrokeTransparency = 0.3
		l.Parent = tag
		tag.StudsOffset = Vector3.new(0, 4.5, 0)
		tag.Parent = r.model.PrimaryPart or r.model:FindFirstChildWhichIsA("BasePart", true)
	end
	broadcast()
	task.wait(Config.Race.Countdown)
	state.phase = "Racing"
	state.endsAt = 0
	broadcast()
	Remotes.FX:FireAllClients("RaceStart", {})

	local finishedCount = 0
	local startTime = os.clock()
	local lastSync = 0
	while finishedCount < #state.racers and os.clock() - startTime < 180 do
		local dt = task.wait(0.1)
		for _, r in ipairs(state.racers) do
			if not r.finished then
				local s = r.stats
				local speed = 10 + math.min(s.speed, 60) * 0.9
				-- Endurance : la vitesse chute apres 45 % de la course selon la stamina
				if r.progress / total > 0.45 then
					local stamina = math.min(s.stamina, 60)
					speed = speed * (0.45 + stamina / 100)
				end
				-- Chance : rafales aleatoires
				if math.random() < math.min(s.luck, 60) / 400 then
					speed = speed * 1.8
				end
				speed = speed * (0.92 + math.random() * 0.16)
				r.progress += speed * dt
				if r.progress >= total then
					r.progress = total
					r.finished = true
					finishedCount += 1
					r.rank = finishedCount
				end
				local pos, nextPoint = pointAt(points, r.progress)
				local look = CFrame.lookAt(pos, Vector3.new(nextPoint.X, pos.Y, nextPoint.Z))
				local bob = math.abs(math.sin(os.clock() * 12 + r.lane)) * 0.6
				r.model:PivotTo(look * CFrame.new(r.lane, -0.9 + bob * 0.3, 0))
			end
		end
		if os.clock() - lastSync > 0.5 then
			lastSync = os.clock()
			broadcast({ total = total })
		end
	end
	-- Classement final
	table.sort(state.racers, function(a, b)
		return (a.rank or 99) < (b.rank or 99)
	end)
	state.phase = "Finished"
	state.endsAt = workspace:GetServerTimeNow() + 8
	local results = {}
	for i, r in ipairs(state.racers) do
		r.rank = r.rank or i
		table.insert(results, { name = r.name, petId = r.petId, evo = r.evo, rank = r.rank, userId = r.player and r.player.UserId or 0 })
		if r.player and r.player.Parent == Players then
			local data = DataService.Get(r.player)
			if data then
				data.Races += 1
				local reward = (r.rank == 1) and state.type.reward or (r.rank == 2 and math.floor(state.type.reward * 0.4) or math.floor(state.type.reward * 0.15))
				if r.rank == 1 then
					data.RaceWins += 1
				end
				PetService.AddCoins(r.player, reward)
				PetService.Sync(r.player)
				Remotes.Notify:FireClient(r.player, (r.rank == 1 and "🥇 VICTOIRE ! " or (r.rank == 2 and "🥈 " or "🏁 ")) .. "Course terminee : +" .. reward .. " coins", r.rank == 1 and "gold" or "good")
			end
		end
	end
	local winner = state.racers[1]
	Remotes.Notify:FireAllClients("🏆 " .. winner.name .. " remporte la course " .. state.type.icon .. " " .. state.type.name .. " avec " .. PetModel.DisplayName(winner.petId, winner.evo) .. " !", "gold")
	broadcast({ results = results })
	Remotes.FX:FireAllClients("RaceEnd", { winnerUserId = winner.player and winner.player.UserId or 0, position = winner.model and winner.model:GetPivot().Position or nil })
	task.wait(8)
	for _, r in ipairs(state.racers) do
		if r.model then
			r.model:Destroy()
		end
	end
	state.phase = "Idle"
	state.type = nil
	state.racers = {}
	state.endsAt = 0
	broadcast()
end

function RaceService.Init()
	runnersFolder = workspace:FindFirstChild("Racers") or Instance.new("Folder")
	runnersFolder.Name = "Racers"
	runnersFolder.Parent = workspace
	Remotes.Race.OnServerEvent:Connect(function(player, action, a, b)
		if action == "join" then
			join(player, tostring(a), b)
		elseif action == "state" then
			broadcast()
		end
	end)
	Players.PlayerAdded:Connect(function()
		task.wait(1)
		broadcast()
	end)
end

return RaceService
