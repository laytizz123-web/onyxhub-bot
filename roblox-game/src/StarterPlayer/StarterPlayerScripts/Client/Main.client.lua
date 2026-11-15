-- Point d'entree client de PET RUSH.

local Modules = script.Parent.Modules
local HUD = require(Modules.HUD)
local Effects = require(Modules.Effects)
local PetFollow = require(Modules.PetFollow)
local WorldIcons = require(Modules.WorldIcons)

HUD.Init()
Effects.Init(HUD)
PetFollow.Init()
task.spawn(WorldIcons.Init)
