-- Point d'entree client de WINDMAIL.
local Modules = script.Parent.Modules

local function start(name, ...)
	local args = table.pack(...)
	local ok, err = pcall(function()
		require(Modules[name]).Init(table.unpack(args, 1, args.n))
	end)
	if not ok then
		warn("[Windmail] Demarrage de " .. name .. " : " .. tostring(err))
	end
end

start("Glider")
start("HUD")
start("Effects")
local HUD = require(Modules.HUD)
local screen = game:GetService("Players").LocalPlayer.PlayerGui:WaitForChild("WindmailHUD")
start("Navigator", screen)
