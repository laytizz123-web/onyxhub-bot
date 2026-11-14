-- Point d'entree serveur d'ONYX ARENA.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

require(ReplicatedStorage.Shared.Remotes) -- cree les RemoteEvents avant tout

local Modules = script.Parent.Modules
local MapBuilder = require(Modules.MapBuilder)
local DataService = require(Modules.DataService)
local RoundManager = require(Modules.RoundManager)
local AbilityService = require(Modules.AbilityService)

MapBuilder.Build()
DataService.Init()
AbilityService.Init(RoundManager)
RoundManager.Start()

print("[OnyxArena] Serveur pret.")
