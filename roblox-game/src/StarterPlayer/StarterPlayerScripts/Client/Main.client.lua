-- Point d'entree client d'ONYX BATTLEGROUNDS.

local Modules = script.Parent.Modules
local Input = require(Modules.Input)
local HUD = require(Modules.HUD)
local Effects = require(Modules.Effects)

Input.Init()
HUD.Init(Input)
Effects.Init(HUD)
