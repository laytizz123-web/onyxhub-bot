-- Boucle de jeu : attente -> intermission -> manche -> fin.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Ball = require(script.Parent.BallController)
local MapBuilder = require(script.Parent.MapBuilder)
local DataService = require(script.Parent.DataService)

local RoundManager = {}

local alive = {} -- [Player] = true
local participants = {}
local ball = nil
local practice = false
local roundDeflects = {}

local state = {
	phase = "Waiting",
	message = "",
	timer = 0,
	aliveCount = 0,
	totalCount = 0,
	practice = false,
	winnerUserId = 0,
}

local function countAlive()
	local n = 0
	for p in pairs(alive) do
		if p.Parent == Players then
			n += 1
		else
			alive[p] = nil
		end
	end
	return n
end

local function getAliveList()
	local list = {}
	for p in pairs(alive) do
		if p.Parent == Players then
			table.insert(list, p)
		end
	end
	return list
end

local function broadcast()
	state.aliveCount = countAlive()
	state.totalCount = #participants
	state.practice = practice
	Remotes.RoundState:FireAllClients(state)
end

local function setPhase(phase, message, timer, winnerUserId)
	state.phase = phase
	state.message = message or ""
	state.timer = timer or 0
	state.winnerUserId = winnerUserId or 0
	broadcast()
end

local function notify(player, text, kind)
	if player then
		Remotes.Notify:FireClient(player, text, kind or "info")
	else
		Remotes.Notify:FireAllClients(text, kind or "info")
	end
end

local function getRoot(player)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hrp and hum and hum.Health > 0 then
		return hrp, hum
	end
	return nil, nil
end

local function getReadyPlayers()
	local list = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if getRoot(p) then
			table.insert(list, p)
		end
	end
	return list
end

local function eliminate(player, reason)
	if not alive[player] then
		return
	end
	alive[player] = nil
	local _, hum = getRoot(player)
	if hum then
		hum.Health = 0
	end
	notify(nil, player.DisplayName .. " " .. reason, "danger")
	broadcast()
end

local function teleportToLobby(player)
	local hrp = getRoot(player)
	if hrp then
		hrp.CFrame = CFrame.new(MapBuilder.GetLobbySpawn())
	end
end

local function runRound(ready)
	participants = ready
	alive = {}
	roundDeflects = {}
	for _, p in ipairs(ready) do
		alive[p] = true
		roundDeflects[p] = 0
	end

	-- Placement et gel des joueurs
	local spawns = MapBuilder.GetSpawnPoints(#ready)
	for i, p in ipairs(ready) do
		local hrp = getRoot(p)
		if hrp then
			hrp.CFrame = CFrame.lookAt(spawns[i], Config.Arena.Center + Vector3.new(0, 4, 0))
			hrp.AssemblyLinearVelocity = Vector3.zero
			hrp.Anchored = true
		end
	end

	for t = Config.Round.Countdown, 1, -1 do
		setPhase("Starting", practice and "MODE ENTRAINEMENT" or "PREPAREZ-VOUS", t)
		task.wait(1)
	end

	for _, p in ipairs(ready) do
		local hrp = getRoot(p)
		if hrp then
			hrp.Anchored = false
		end
	end

	ball = Ball.new({
		practice = practice,
		isAlive = function(p)
			return alive[p] == true
		end,
		getAlive = getAliveList,
		onHit = function(p)
			if practice then
				notify(p, "Touche ! Le ballon repart du centre.", "danger")
			else
				eliminate(p, "a ete elimine !")
			end
		end,
		onDeflect = function(p)
			roundDeflects[p] = (roundDeflects[p] or 0) + 1
			DataService.Add(p, "Coins", Config.Rewards.Deflect)
			DataService.Add(p, "Deflects", 1)
		end,
	})

	setPhase("Playing", practice and "ENTRAINEMENT : renvoie le ballon !" or "SURVIS !", Config.Round.Duration)

	local startTime = os.clock()
	local overdrive = false
	local lastBroadcast = 0
	while true do
		task.wait(0.2)
		local elapsed = os.clock() - startTime
		local remaining = math.max(0, Config.Round.Duration - elapsed)
		state.timer = math.ceil(remaining)

		if not overdrive and remaining <= 0 then
			overdrive = true
			ball:setOverdrive(true)
			state.message = "OVERDRIVE !"
			notify(nil, "OVERDRIVE ! Le ballon est dechaine !", "overdrive")
			broadcast()
		end

		local count = countAlive()
		if practice then
			if #Players:GetPlayers() >= Config.Round.MinPlayers or count == 0 then
				break
			end
		elseif count <= 1 then
			break
		end

		if os.clock() - lastBroadcast >= 1 then
			lastBroadcast = os.clock()
			broadcast()
		end
	end

	ball:destroy()
	ball = nil

	-- Fin de manche
	local winner = nil
	if not practice then
		winner = getAliveList()[1]
	end

	if winner then
		local streak = DataService.GetStreak(winner) + 1
		DataService.SetStreak(winner, streak)
		DataService.Add(winner, "Wins", 1)
		local reward = Config.Rewards.Win + (streak > 1 and Config.Rewards.StreakBonus * (streak - 1) or 0)
		DataService.Add(winner, "Coins", reward)
		notify(winner, "+" .. reward .. " pieces (serie x" .. streak .. ")", "gold")
		for _, p in ipairs(participants) do
			if p ~= winner and p.Parent == Players then
				DataService.SetStreak(p, 0)
				DataService.Add(p, "Coins", Config.Rewards.Survive)
			end
		end
		setPhase("Ending", winner.DisplayName .. " remporte la manche !", Config.Round.EndDelay, winner.UserId)
	elseif practice then
		setPhase("Ending", "Entrainement termine", 3)
	else
		setPhase("Ending", "Match nul !", Config.Round.EndDelay)
	end

	task.wait(practice and 3 or Config.Round.EndDelay)

	for p in pairs(alive) do
		if p.Parent == Players then
			teleportToLobby(p)
		end
	end
	alive = {}
	participants = {}
	broadcast()
end

local function mainLoop()
	while true do
		while #Players:GetPlayers() == 0 do
			setPhase("Waiting", "En attente de joueurs...", 0)
			task.wait(1)
		end

		for t = Config.Round.Intermission, 1, -1 do
			local n = #getReadyPlayers()
			local msg
			if n >= Config.Round.MinPlayers then
				msg = "Prochaine manche dans"
			else
				msg = "Entrainement dans (" .. n .. "/" .. Config.Round.MinPlayers .. " joueurs)"
			end
			setPhase("Intermission", msg, t)
			task.wait(1)
		end

		local ready = getReadyPlayers()
		if #ready == 0 then
			continue
		end
		practice = #ready < Config.Round.MinPlayers
		local ok, err = pcall(runRound, ready)
		if not ok then
			warn("[OnyxArena] Erreur pendant la manche : " .. tostring(err))
			if ball then
				ball:destroy()
				ball = nil
			end
			alive = {}
			participants = {}
		end
	end
end

-- Chute hors de la carte
local function fallWatcher()
	while true do
		task.wait(0.5)
		for _, p in ipairs(Players:GetPlayers()) do
			local hrp, hum = getRoot(p)
			if hrp and hrp.Position.Y < Config.Arena.KillHeight then
				if alive[p] then
					eliminate(p, "est tombe dans le vide !")
				else
					hum.Health = 0
				end
			end
		end
	end
end

function RoundManager.HandleDeflect(player)
	if ball and alive[player] then
		ball:deflect(player)
	end
end

function RoundManager.GetBall()
	return ball
end

function RoundManager.IsAlive(player)
	return alive[player] == true
end

function RoundManager.GetState()
	return state
end

function RoundManager.Start()
	Players.PlayerRemoving:Connect(function(player)
		alive[player] = nil
	end)
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			task.wait(0.1)
			broadcast()
		end)
		Remotes.RoundState:FireClient(player, state)
	end)
	task.spawn(fallWatcher)
	task.spawn(mainLoop)
end

return RoundManager
