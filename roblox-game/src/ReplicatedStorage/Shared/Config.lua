-- Configuration centrale d'ONYX FARM.
-- Tout l'equilibrage du jeu se regle ici.

local Config = {}

Config.GameName = "ONYX FARM"
Config.StartCoins = 60

Config.Colors = {
	Accent = Color3.fromRGB(80, 220, 120),
	Accent2 = Color3.fromRGB(255, 150, 60),
	Gold = Color3.fromRGB(255, 200, 40),
	Danger = Color3.fromRGB(255, 80, 80),
	Sky = Color3.fromRGB(90, 190, 255),
	Dark = Color3.fromRGB(28, 36, 30),
	Grass = Color3.fromRGB(96, 170, 70),
	Soil = Color3.fromRGB(96, 66, 42),
	SoilWet = Color3.fromRGB(70, 46, 30),
	Wood = Color3.fromRGB(150, 105, 60),
}

-- Plantes : ordre = ordre d'affichage dans la boutique.
-- price : prix de la graine | growTime : secondes | value : prix de vente de base
-- baseWeight : poids moyen (kg) | multi : repousse apres recolte | stock : {chance, min, max}
Config.Plants = {
	{ id = "Carotte", price = 10, growTime = 25, value = 18, baseWeight = 0.3, multi = false, shape = "root", color = Color3.fromRGB(255, 130, 30), stock = { 1, 5, 20 } },
	{ id = "Fraise", price = 50, growTime = 50, value = 14, baseWeight = 0.3, multi = true, shape = "bush", color = Color3.fromRGB(255, 60, 80), stock = { 1, 2, 8 } },
	{ id = "Myrtille", price = 400, growTime = 80, value = 20, baseWeight = 0.2, multi = true, shape = "bush", color = Color3.fromRGB(70, 90, 220), stock = { 1, 1, 5 } },
	{ id = "Tomate", price = 800, growTime = 120, value = 30, baseWeight = 0.5, multi = true, shape = "bush", color = Color3.fromRGB(230, 40, 40), stock = { 0.8, 1, 3 } },
	{ id = "Citrouille", price = 2500, growTime = 240, value = 350, baseWeight = 7, multi = false, shape = "big", color = Color3.fromRGB(255, 140, 20), stock = { 0.6, 1, 2 } },
	{ id = "Pasteque", price = 5000, growTime = 300, value = 800, baseWeight = 8, multi = false, shape = "big", color = Color3.fromRGB(60, 170, 70), stock = { 0.5, 1, 2 } },
	{ id = "Bambou", price = 15000, growTime = 200, value = 1400, baseWeight = 4, multi = false, shape = "tall", color = Color3.fromRGB(120, 200, 80), stock = { 0.4, 1, 2 } },
	{ id = "Cactus", price = 30000, growTime = 400, value = 3200, baseWeight = 6, multi = true, shape = "cactus", color = Color3.fromRGB(60, 150, 70), stock = { 0.3, 1, 1 } },
	{ id = "Fruit du dragon", price = 80000, growTime = 600, value = 9000, baseWeight = 1.2, multi = true, shape = "bush", color = Color3.fromRGB(255, 70, 160), stock = { 0.2, 1, 1 } },
	{ id = "Fleur de lune", price = 250000, growTime = 900, value = 40000, baseWeight = 0.8, multi = true, shape = "bush", color = Color3.fromRGB(180, 120, 255), stock = { 0.08, 1, 1 } },
}

Config.PlantById = {}
for index, plant in ipairs(Config.Plants) do
	plant.index = index
	Config.PlantById[plant.id] = plant
end

-- Mutations : multiplicateur de valeur et couleur du fruit.
Config.Mutations = {
	Mouille = { mult = 2, color = Color3.fromRGB(120, 200, 255), label = "Mouille" },
	Gele = { mult = 10, color = Color3.fromRGB(190, 240, 255), label = "Gele" },
	Choc = { mult = 100, color = Color3.fromRGB(255, 255, 120), label = "Choc" },
	Dore = { mult = 20, color = Color3.fromRGB(255, 215, 0), label = "Dore" },
	ArcEnCiel = { mult = 50, color = Color3.fromRGB(255, 120, 255), label = "Arc-en-ciel" },
}
Config.MutationOrder = { "Dore", "ArcEnCiel", "Mouille", "Gele", "Choc" }

-- Chances a la maturation d'une plante
Config.RipeMutationChance = { Dore = 0.02, ArcEnCiel = 0.002 }

-- Meteo : duree, multiplicateur de croissance et mutation appliquee
Config.Weather = {
	MinInterval = 150,
	MaxInterval = 280,
	Events = {
		{ id = "Pluie", label = "PLUIE", growth = 2, duration = 90, mutation = "Mouille", mutationChance = 0.08, tick = 5, weight = 5 },
		{ id = "Orage", label = "ORAGE", growth = 2.5, duration = 75, mutation = "Mouille", mutationChance = 0.05, tick = 5, lightning = 9, weight = 3 },
		{ id = "Gel", label = "VAGUE DE FROID", growth = 0.6, duration = 70, mutation = "Gele", mutationChance = 0.06, tick = 6, weight = 2 },
	},
}

Config.Plot = {
	Count = 8,
	Grid = 7, -- 7x7 cases
	TileSize = 4,
	TileGap = 0.6,
	-- Au depart : le carre central 3x3 (9 cases). Chaque palier debloque une couronne :
	-- palier 1 = 25 cases (800), palier 2 = 49 cases (15000)
	ExpandPrices = { 800, 15000 },
	Distance = 90, -- distance du centre
}

Config.Shop = {
	RestockInterval = 300, -- secondes
}

Config.Water = {
	Cooldown = 6,
	Boost = 0.2, -- +20 % de croissance par arrosage
}

Config.Weight = {
	Min = 0.6,
	Max = 3.5, -- un fruit peut peser jusqu'a 3,5x le poids moyen (rare)
	GiantThreshold = 2, -- affichage "Geant"
}

Config.OfflineGrowthCap = 2 * 3600 -- 2 h de croissance hors ligne max

return Config
