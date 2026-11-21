-- Echanges securises entre joueurs.
-- Demande -> acceptation -> chacun ajoute jusqu'a 9 reliques -> les deux valident -> compte a
-- rebours -> le serveur reverifie TOUT (propriete, verrou, place) puis echange en une fois et
-- sauvegarde immediatement les deux joueurs. Toute modification annule les validations.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local F = require(ReplicatedStorage.Shared.Formulas)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local DataService = require(script.Parent.DataService)
local Actions = require(script.Parent.Actions)
local RelicService = require(script.Parent.RelicService)

local TradeService = {}

local requests = {} -- [target] = { [from] = os.clock() }
local sessions = {} -- [player] = session ; session = { a, b, offer = {[a]={}, [b]={}}, ready = {}, token }

local function other(s, p)
	return s.a == p and s.b or s.a
end

local function describe(s, viewer)
	local function list(p)
		local data = DataService.Get(p)
		local out = {}
		for _, uid in ipairs(s.offer[p]) do
			local item = data and data.Relics[tostring(uid)]
			if item then
				table.insert(out, { uid = uid, id = item.id })
			end
		end
		return out
	end
	local o = other(s, viewer)
	return {
		active = true,
		partner = o.DisplayName,
		partnerId = o.UserId,
		mine = list(viewer),
		theirs = list(o),
		myReady = s.ready[viewer] == true,
		theirReady = s.ready[o] == true,
		countdown = s.countdownEnd,
	}
end

local function push(s)
	for _, p in ipairs({ s.a, s.b }) do
		if p.Parent == Players then
			Remotes.Trade:FireClient(p, "session", describe(s, p))
		end
	end
end

local function close(s, reason)
	for _, p in ipairs({ s.a, s.b }) do
		sessions[p] = nil
		if p.Parent == Players then
			Remotes.Trade:FireClient(p, "closed", { reason = reason })
		end
	end
end

local function resetReady(s)
	s.ready = {}
	s.countdownEnd = nil
	s.token = (s.token or 0) + 1
end

local function execute(s)
	local da, db = DataService.Get(s.a), DataService.Get(s.b)
	if not (da and db) then
		return close(s, "Echange annule.")
	end
	-- verification complete
	for _, pair in ipairs({ { s.a, da }, { s.b, db } }) do
		local p, data = pair[1], pair[2]
		for _, uid in ipairs(s.offer[p]) do
			local item = data.Relics[tostring(uid)]
			if not item or item.locked then
				return close(s, "Echange annule : une relique n'est plus disponible.")
			end
		end
	end
	if DataService.Count(da) - #s.offer[s.a] + #s.offer[s.b] > F.InventoryCap(da) or DataService.Count(db) - #s.offer[s.b] + #s.offer[s.a] > F.InventoryCap(db) then
		return close(s, "Echange annule : inventaire plein.")
	end
	-- transfert
	local moveAB, moveBA = {}, {}
	for _, uid in ipairs(s.offer[s.a]) do
		table.insert(moveAB, da.Relics[tostring(uid)].id)
		RelicService.Unequip(da, uid)
		da.Relics[tostring(uid)] = nil
	end
	for _, uid in ipairs(s.offer[s.b]) do
		table.insert(moveBA, db.Relics[tostring(uid)].id)
		RelicService.Unequip(db, uid)
		db.Relics[tostring(uid)] = nil
	end
	for _, id in ipairs(moveAB) do
		DataService.GiveRelic(s.b, id, true)
	end
	for _, id in ipairs(moveBA) do
		DataService.GiveRelic(s.a, id, true)
	end
	close(s, "Echange reussi !")
	for _, p in ipairs({ s.a, s.b }) do
		DataService.Sync(p)
		task.spawn(DataService.Save, p)
		Remotes.FX:FireClient(p, "TradeDone", {})
	end
end

function TradeService.Init()
	Actions.Register("tradeRequest", function(player, data, targetId)
		local target = Players:GetPlayerByUserId(tonumber(targetId) or 0)
		if not target or target == player or sessions[player] or sessions[target] then
			return Actions.Notify(player, "Echange impossible pour le moment.", "danger")
		end
		requests[target] = requests[target] or {}
		requests[target][player] = os.clock()
		Remotes.Trade:FireClient(target, "request", { from = player.DisplayName, fromId = player.UserId })
		Actions.Notify(player, "Demande envoyee a " .. target.DisplayName, "info")
		return true
	end)
	Actions.Register("tradeAccept", function(player, data, fromId)
		local from = Players:GetPlayerByUserId(tonumber(fromId) or 0)
		local t = requests[player] and from and requests[player][from]
		if not t or os.clock() - t > Config.Trade.RequestTimeout or sessions[player] or sessions[from] then
			return Actions.Notify(player, "Cette demande a expire.", "danger")
		end
		requests[player][from] = nil
		local s = { a = from, b = player, offer = { [from] = {}, [player] = {} }, ready = {}, token = 0 }
		sessions[from] = s
		sessions[player] = s
		push(s)
		return true
	end)
	Actions.Register("tradeDecline", function(player, data, fromId)
		local from = Players:GetPlayerByUserId(tonumber(fromId) or 0)
		if requests[player] and from then
			requests[player][from] = nil
			Remotes.Notify:FireClient(from, player.DisplayName .. " a refuse l'echange.", "info")
		end
		return true
	end)
	Actions.Register("tradeAdd", function(player, data, uid)
		local s = sessions[player]
		uid = tonumber(uid)
		local item = uid and data.Relics[tostring(uid)]
		if not (s and item) or item.locked or table.find(s.offer[player], uid) or #s.offer[player] >= Config.Trade.MaxItems then
			return true
		end
		table.insert(s.offer[player], uid)
		resetReady(s)
		push(s)
		return true
	end)
	Actions.Register("tradeRemove", function(player, data, uid)
		local s = sessions[player]
		local i = s and table.find(s.offer[player], tonumber(uid))
		if i then
			table.remove(s.offer[player], i)
			resetReady(s)
			push(s)
		end
		return true
	end)
	Actions.Register("tradeReady", function(player, data, on)
		local s = sessions[player]
		if not s then
			return true
		end
		s.ready[player] = on == true
		if s.ready[s.a] and s.ready[s.b] then
			s.token += 1
			local token = s.token
			s.countdownEnd = os.time() + Config.Trade.ConfirmTime
			push(s)
			task.delay(Config.Trade.ConfirmTime, function()
				if sessions[s.a] == s and s.token == token and s.ready[s.a] and s.ready[s.b] then
					execute(s)
				end
			end)
		else
			s.countdownEnd = nil
			s.token += 1
			push(s)
		end
		return true
	end)
	Actions.Register("tradeCancel", function(player)
		local s = sessions[player]
		if s then
			close(s, player.DisplayName .. " a annule l'echange.")
		end
		return true
	end)
	Players.PlayerRemoving:Connect(function(p)
		local s = sessions[p]
		if s then
			close(s, "L'autre joueur est parti.")
		end
		requests[p] = nil
	end)
end

return TradeService
