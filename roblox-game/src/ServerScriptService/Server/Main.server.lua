-- Point d'entree serveur de PET RUSH.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

require(ReplicatedStorage.Shared.Remotes) -- cree les RemoteEvents avant tout

local Modules = script.Parent.Modules
local MapBuilder = require(Modules.MapBuilder)
local DataService = require(Modules.DataService)
local PetService = require(Modules.PetService)
local CoinService = require(Modules.CoinService)
local RaceService = require(Modules.RaceService)

MapBuilder.Build()
DataService.Init()
PetService.Init()
CoinService.Init()
RaceService.Init()

print("[PetRush] Serveur pret.")
