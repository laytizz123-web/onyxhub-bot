-- Timbres de collection : colis mystere, timbres caches (secrets), evenements. Bonus de sets.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Progress = require(ReplicatedStorage.Shared.Progress)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local DataService = require(script.Parent.DataService)

local StampService = {}

function StampService.Give(player, stampId)
	local data = DataService.Get(player)
	local stamp = Config.StampById[stampId]
	if not (data and stamp) then
		return false
	end
	local before = Progress.SetBonuses(data.Stamps)
	local first = not data.Stamps[stampId]
	data.Stamps[stampId] = (data.Stamps[stampId] or 0) + 1
	local after = Progress.SetBonuses(data.Stamps)
	Remotes.FX:FireClient(player, "Stamp", { id = stampId, first = first })
	for setId in pairs(after.done) do
		if not before.done[setId] then
			for _, set in ipairs(Config.StampSets) do
				if set.id == setId then
					Remotes.Notify:FireClient(player, "Collection " .. set.name .. " complete ! Bonus : " .. set.bonus, "gold")
					if set.trail then
						data.Trails[set.trail] = true
					end
				end
			end
		end
	end
	DataService.Sync(player)
	return first
end

-- Tirage d'un timbre de colis mystere (rarete ponderee)
function StampService.RollMystery()
	local pool, total = {}, 0
	for _, s in ipairs(Config.Stamps) do
		if s.source == "mystery" then
			local w = Config.StampRarity[s.rarity].weight
			table.insert(pool, { s, w })
			total += w
		end
	end
	local r = math.random() * total
	for _, e in ipairs(pool) do
		r -= e[2]
		if r <= 0 then
			return e[1].id
		end
	end
	return pool[1][1].id
end

function StampService.Init()
	local cooldown = {}
	local function hook(spot)
		spot.CanTouch = true
		spot.Touched:Connect(function(hit)
			local player = Players:GetPlayerFromCharacter(hit.Parent)
			if not player then
				return
			end
			local data = DataService.Get(player)
			local id = spot:GetAttribute("StampId")
			if not data or data.Stamps[id] or (cooldown[player] and os.clock() - cooldown[player] < 1) then
				return
			end
			cooldown[player] = os.clock()
			StampService.Give(player, id)
			Remotes.Notify:FireAllClients(player.DisplayName .. " a decouvert un timbre secret : " .. Config.StampById[id].name .. " !", "gold")
		end)
	end
	for _, s in ipairs(CollectionService:GetTagged("StampSpot")) do
		hook(s)
	end
	CollectionService:GetInstanceAddedSignal("StampSpot"):Connect(hook)
	Players.PlayerRemoving:Connect(function(p)
		cooldown[p] = nil
	end)
end

return StampService
