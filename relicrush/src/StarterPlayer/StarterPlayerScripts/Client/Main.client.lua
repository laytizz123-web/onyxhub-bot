-- Point d'entree client de RELIC RUSH.
local Modules = script.Parent.Modules

local function start(name)
	local ok, err = pcall(function()
		local m = require(Modules[name])
		if m.Init then
			m.Init()
		end
	end)
	if not ok then
		warn("[RelicRush] Demarrage de " .. name .. " : " .. tostring(err))
	end
end

start("HUD")
start("PanelsA")
start("PanelsB")
start("RelicOrbit")
start("Effects")
