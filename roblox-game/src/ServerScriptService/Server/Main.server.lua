-- Point d'entree serveur d'ONYX BATTLEGROUNDS.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

require(ReplicatedStorage.Shared.Remotes) -- cree les RemoteEvents avant tout

local Modules = script.Parent.Modules
local MapBuilder = require(Modules.MapBuilder)
local DataService = require(Modules.DataService)
local ProgressionService = require(Modules.ProgressionService)
local CharacterService = require(Modules.CharacterService)
local CombatService = require(Modules.CombatService)

MapBuilder.Build()
DataService.Init()
ProgressionService.Init(CharacterService)
CharacterService.Init()
CombatService.Init()

print("[OnyxBG] Serveur pret.")
