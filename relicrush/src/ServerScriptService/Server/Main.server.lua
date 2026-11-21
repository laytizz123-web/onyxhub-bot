-- Point d'entree serveur de RELIC RUSH : chaque service demarre isole (une erreur n'arrete pas les autres).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
require(ReplicatedStorage.Shared.Remotes)

local Modules = script.Parent.Modules

local function start(name, method)
	local ok, err = pcall(function()
		require(Modules[name])[method or "Init"]()
	end)
	if not ok then
		warn("[RelicRush] Demarrage de " .. name .. " : " .. tostring(err))
	end
end

start("WorldBuilder", "Build")
start("DataService")
start("Actions")
start("Targets")
start("TreasureService")
start("RelicService")
start("ProgressService")
start("BossService")
start("TradeService")
start("QueryService")
print("[RelicRush] Serveur pret.")
