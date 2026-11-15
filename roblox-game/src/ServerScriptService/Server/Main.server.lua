-- Point d'entree serveur d'ONYX FARM.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

require(ReplicatedStorage.Shared.Remotes) -- cree les RemoteEvents avant tout

local Modules = script.Parent.Modules
local MapBuilder = require(Modules.MapBuilder)
local DataService = require(Modules.DataService)
local PlotService = require(Modules.PlotService)
local WeatherService = require(Modules.WeatherService)
local ShopService = require(Modules.ShopService)

MapBuilder.Build()
DataService.Init()
PlotService.Init(WeatherService)
WeatherService.Init(PlotService)
ShopService.Init(PlotService)

print("[OnyxFarm] Serveur pret.")
