-- Meteo dynamique : pluie, orage (eclairs), vague de froid. Mutations sur les plantes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local WeatherService = {}

local current = nil -- event table ou nil
local endsAt = 0
local PlotService -- injecte

local function broadcast(player)
	local payload = {
		id = current and current.id or "Clair",
		label = current and current.label or "",
		endsAt = current and endsAt or 0,
		serverTime = workspace:GetServerTimeNow(),
	}
	if player then
		Remotes.Weather:FireClient(player, payload)
	else
		Remotes.Weather:FireAllClients(payload)
	end
end

local function pickEvent()
	local total = 0
	for _, e in ipairs(Config.Weather.Events) do
		total += e.weight
	end
	local r = math.random() * total
	for _, e in ipairs(Config.Weather.Events) do
		r -= e.weight
		if r <= 0 then
			return e
		end
	end
	return Config.Weather.Events[1]
end

local function runEvent(event)
	current = event
	endsAt = workspace:GetServerTimeNow() + event.duration
	broadcast()
	Remotes.Notify:FireAllClients(event.label .. " ! Croissance x" .. event.growth, "weather")

	local lastTick = os.clock()
	local lastLightning = os.clock()
	local startTime = os.clock()
	while os.clock() - startTime < event.duration do
		task.wait(0.5)
		if event.mutation and os.clock() - lastTick >= event.tick then
			lastTick = os.clock()
			PlotService.ApplyWeatherMutation(event.mutation, event.mutationChance)
		end
		if event.lightning and os.clock() - lastLightning >= event.lightning then
			lastLightning = os.clock()
			local tile = PlotService.RandomPlantedTile()
			if tile then
				PlotService.AddMutation(tile, "Choc")
				Remotes.FX:FireAllClients("Lightning", { position = tile.Position })
			else
				local angle = math.random() * math.pi * 2
				Remotes.FX:FireAllClients("Lightning", { position = Vector3.new(math.cos(angle) * 120, 0, math.sin(angle) * 120) })
			end
		end
	end

	current = nil
	endsAt = 0
	broadcast()
	Remotes.Notify:FireAllClients("Le ciel se degage.", "info")
end

function WeatherService.GetGrowthMultiplier()
	return current and current.growth or 1
end

function WeatherService.GetCurrent()
	return current
end

function WeatherService.Init(plotService)
	PlotService = plotService
	Players.PlayerAdded:Connect(function(player)
		task.wait(1)
		broadcast(player)
	end)
	task.spawn(function()
		task.wait(45) -- premiere meteo rapide pour montrer le systeme
		while true do
			runEvent(pickEvent())
			task.wait(math.random(Config.Weather.MinInterval, Config.Weather.MaxInterval))
		end
	end)
end

return WeatherService
