-- Calculs partages client/serveur : valeur d'un fruit, libelles.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local Economy = {}

function Economy.value(fruit)
	local plant = Config.PlantById[fruit.id]
	if not plant then
		return 0
	end
	local value = plant.value * (fruit.weight / plant.baseWeight)
	for _, name in ipairs(fruit.mutations or {}) do
		local mutation = Config.Mutations[name]
		if mutation then
			value = value * mutation.mult
		end
	end
	return math.floor(value + 0.5)
end

function Economy.mutationLabel(mutations)
	local labels = {}
	for _, name in ipairs(Config.MutationOrder) do
		if table.find(mutations or {}, name) then
			local mutation = Config.Mutations[name]
			table.insert(labels, mutation and mutation.label or name)
		end
	end
	return table.concat(labels, " ")
end

function Economy.fruitName(fruit)
	local plant = Config.PlantById[fruit.id]
	local base = plant and plant.id or fruit.id
	local label = Economy.mutationLabel(fruit.mutations)
	local giant = plant and (fruit.weight / plant.baseWeight) >= Config.Weight.GiantThreshold
	local name = base
	if label ~= "" then
		name = label .. " " .. name
	end
	if giant then
		name = name .. " GEANT"
	end
	return name
end

function Economy.formatWeight(weight)
	if weight >= 1 then
		return string.format("%.1f kg", weight)
	end
	return string.format("%d g", math.floor(weight * 1000 + 0.5))
end

function Economy.formatCoins(amount)
	local s = tostring(math.floor(amount))
	local formatted = s:reverse():gsub("(%d%d%d)", "%1 "):reverse()
	return (formatted:gsub("^%s+", ""))
end

-- Poids aleatoire : la plupart des fruits sont proches de la moyenne, rares geants.
function Economy.rollWeight(plant)
	local r = math.random()
	local factor = Config.Weight.Min + (Config.Weight.Max - Config.Weight.Min) * (r ^ 4)
	return math.floor(plant.baseWeight * factor * 1000 + 0.5) / 1000
end

return Economy
