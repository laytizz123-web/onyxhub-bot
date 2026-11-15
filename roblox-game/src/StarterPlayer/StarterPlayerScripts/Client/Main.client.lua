-- Point d'entree client de PET RUSH.
-- Chaque module demarre separement : une erreur dans l'un n'empeche plus les autres de fonctionner.

local Modules = script.Parent.Modules

local function start(name, ...)
	local args = table.pack(...)
	local ok, err = pcall(function()
		local module = require(Modules[name])
		module.Init(table.unpack(args, 1, args.n))
	end)
	if not ok then
		warn("[PetRush] Erreur au demarrage de " .. name .. " : " .. tostring(err))
	end
end

local HUD = require(Modules.HUD)
start("HUD")
start("Effects", HUD)
start("PetFollow")
task.spawn(start, "WorldIcons")
