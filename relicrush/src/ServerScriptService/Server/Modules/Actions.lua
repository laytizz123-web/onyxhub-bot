-- Routeur des actions client -> serveur (un seul RemoteEvent "Action").
-- Chaque service enregistre ses actions ; apres chaque action le joueur est resynchronise
-- (sauf si la fonction renvoie true). Limite de debit anti-spam.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local DataService = require(script.Parent.DataService)

local Actions = {}
local handlers = {}
local rate = {}

function Actions.Register(name, fn)
	handlers[name] = fn
end

function Actions.Notify(player, text, kind)
	Remotes.Notify:FireClient(player, text, kind or "info")
end

function Actions.Init()
	Remotes.Action.OnServerEvent:Connect(function(player, name, ...)
		if type(name) ~= "string" then
			return
		end
		local fn = handlers[name]
		local data = DataService.Get(player)
		if not (fn and data) then
			return
		end
		local r = rate[player]
		local now = os.clock()
		if not r or now - r.t > 1 then
			r = { t = now, n = 0 }
			rate[player] = r
		end
		r.n += 1
		if r.n > 25 then
			return
		end
		local ok, skip = pcall(fn, player, data, ...)
		if not ok then
			warn("[RelicRush] Action " .. name .. " : " .. tostring(skip))
		end
		if not skip then
			DataService.Sync(player)
		end
	end)
	game:GetService("Players").PlayerRemoving:Connect(function(p)
		rate[p] = nil
	end)
end

return Actions
