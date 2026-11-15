-- Point d'entree serveur de PET RUSH.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

require(ReplicatedStorage.Shared.Remotes) -- cree les RemoteEvents avant tout

local Modules = script.Parent.Modules

local function start(name, method)
	local ok, err = pcall(function()
		require(Modules[name])[method or "Init"]()
	end)
	if not ok then
		warn("[PetRush] Erreur au demarrage de " .. name .. " : " .. tostring(err))
	end
end

start("MapBuilder", "Build")
start("DataService")
start("PetService")
start("CoinService")
start("RaceService")

print("[PetRush] Serveur pret.")
