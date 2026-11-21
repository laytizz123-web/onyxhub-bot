-- Requetes client -> serveur avec reponse (RemoteFunction) : classements globaux.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local DataService = require(script.Parent.DataService)

local QueryService = {}

function QueryService.Init()
	local last = {}
	Remotes.Query.OnServerInvoke = function(player, kind, arg)
		if last[player] and os.clock() - last[player] < 0.5 then
			return nil
		end
		last[player] = os.clock()
		if kind == "top" and (arg == "Power" or arg == "Rebirths" or arg == "Index") then
			return DataService.GetTop(arg)
		end
		return nil
	end
	game:GetService("Players").PlayerRemoving:Connect(function(p)
		last[p] = nil
	end)
end

return QueryService
