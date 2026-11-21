-- Point d'entree serveur de WINDMAIL.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
require(ReplicatedStorage.Shared.Remotes)

local Modules = script.Parent.Modules

local function start(name, method)
	local ok, err = pcall(function()
		require(Modules[name])[method or "Init"]()
	end)
	if not ok then
		warn("[Windmail] Demarrage de " .. name .. " : " .. tostring(err))
	end
end

start("WorldBuilder", "Build")
start("DataService")
start("StampService")
start("ParcelService")
start("ShopService")
start("EventService")
start("BoardService")
print("[Windmail] Serveur pret.")
