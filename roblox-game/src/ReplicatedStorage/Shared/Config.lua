-- Configuration centrale de PET RUSH : raretes, pets, oeufs, zones, evolutions, courses.

local Config = {}

Config.GameName = "PET RUSH"
Config.StartCoins = 100
Config.MaxEquipped = 3
Config.MaxPets = 60

Config.Colors = {
	Accent = Color3.fromRGB(80, 200, 255),
	Accent2 = Color3.fromRGB(255, 120, 200),
	Gold = Color3.fromRGB(255, 200, 40),
	Danger = Color3.fromRGB(255, 80, 80),
	Panel = Color3.fromRGB(28, 26, 46),
	Panel2 = Color3.fromRGB(14, 12, 26),
	Grass = Color3.fromRGB(110, 200, 90),
}

-- Les icones sont integrees au jeu (assets/icons -> IconData.lua). Pour utiliser une image uploadee a la place,
-- mets son ID ici, par ex. Config.IconImages.pets = "rbxassetid://1234567890".
Config.IconImages = {
	index = "", eggs = "", pets = "", shop = "", rewards = "", worlds = "", race = "", leaderboard = "", trading = "",
	quests = "", settings = "", inventory = "", teleport = "", daily = "", codes = "", ranks = "", achievements = "",
	freegift = "", events = "", exit = "", coin = "", speed = "", power = "", stamina = "", luck = "", lock = "",
	gem = "", star = "", close = "", paw = "", egg = "",
}

-- Images des pets : integrees depuis assets/pets (PetImageData.lua). Pour utiliser une image uploadee,
-- mets son ID ici, par ex. Config.PetImages.Chaton = "rbxassetid://1234567890".
Config.PetImages = {}

-- Teinte appliquee aux images de pets selon l'evolution
Config.EvolutionTint = {
	Normal = Color3.new(1, 1, 1),
	Golden = Color3.fromRGB(255, 225, 110),
	Rainbow = Color3.fromRGB(255, 185, 255),
	Cosmic = Color3.fromRGB(175, 150, 255),
}

-- Modeles importes (fichiers .glb) : orientation.
-- ResetRotation : annule la rotation ajoutee par l'importateur (les .glb sont faits debout, face a l'avant).
-- Extra : rotation en degres ajoutee ensuite, si besoin (ex. Vector3.new(0, 180, 0) si les pets sont de dos,
--         Vector3.new(-90, 0, 0) ou Vector3.new(90, 0, 0) s'ils sont encore couches).
Config.ImportedPetRotation = {
	ResetRotation = true,
	Extra = Vector3.new(0, 0, 0),
}

-- Codes cadeaux (a changer librement)
Config.Codes = {
	PETRUSH = 500,
	LAUNCH = 1500,
	RACE = 1000,
}

Config.Icons = {
	coins = "🪙", pets = "🐾", egg = "🥚", index = "📖", race = "🏁", zone = "🗺️", daily = "🎁", chest = "🎁",
	speed = "⚡", power = "💪", stamina = "🛡️", luck = "🍀", evolve = "🧬", equip = "✅", trophy = "🏆",
	lock = "🔒", star = "⭐", info = "ℹ️", warning = "⚠️", delete = "🗑️", leader = "📈",
}

-- Raretes (ordre croissant)
Config.Rarities = {
	{ id = "Common", name = "Common", icon = "⚪", color = Color3.fromRGB(210, 210, 210), weight = 50, power = 1 },
	{ id = "Uncommon", name = "Uncommon", icon = "🟢", color = Color3.fromRGB(90, 220, 90), weight = 28, power = 2 },
	{ id = "Rare", name = "Rare", icon = "🔵", color = Color3.fromRGB(70, 140, 255), weight = 14, power = 4 },
	{ id = "Epic", name = "Epic", icon = "🟣", color = Color3.fromRGB(190, 90, 255), weight = 6, power = 8 },
	{ id = "Legendary", name = "Legendary", icon = "🟡", color = Color3.fromRGB(255, 210, 50), weight = 1.6, power = 18 },
	{ id = "Mythical", name = "Mythical", icon = "🔴", color = Color3.fromRGB(255, 70, 70), weight = 0.35, power = 45 },
	{ id = "Secret", name = "Secret", icon = "🌈", color = Color3.fromRGB(255, 150, 255), weight = 0.05, power = 120 },
}
Config.RarityById = {}
for i, r in ipairs(Config.Rarities) do
	r.index = i
	Config.RarityById[r.id] = r
end

-- Evolutions : Normal -> Golden -> Rainbow -> Cosmic (3 exemplaires identiques pour evoluer)
Config.Evolutions = {
	{ id = "Normal", name = "", icon = "", mult = 1 },
	{ id = "Golden", name = "Golden", icon = "✨", mult = 2.5, color = Color3.fromRGB(255, 215, 0) },
	{ id = "Rainbow", name = "Rainbow", icon = "🌈", mult = 6, color = Color3.fromRGB(255, 120, 255) },
	{ id = "Cosmic", name = "Cosmic", icon = "🌌", mult = 15, color = Color3.fromRGB(140, 80, 255) },
}
Config.EvolveCost = 3

-- Pets : shape = cat | dog | bunny | bird | dragon | snake | bear | blob
-- speed / stamina / luck : 1 a 10. power vient de la rarete.
Config.Pets = {
	-- Village
	{ id = "Chaton", icon = "🐱", rarity = "Common", egg = "Village", shape = "cat", color = Color3.fromRGB(255, 180, 90), speed = 5, stamina = 3, luck = 3 },
	{ id = "Chiot", icon = "🐶", rarity = "Common", egg = "Village", shape = "dog", color = Color3.fromRGB(190, 140, 90), speed = 4, stamina = 5, luck = 2 },
	{ id = "Lapin", icon = "🐰", rarity = "Uncommon", egg = "Village", shape = "bunny", color = Color3.fromRGB(240, 240, 250), speed = 7, stamina = 3, luck = 5 },
	{ id = "Renard", icon = "🦊", rarity = "Rare", egg = "Village", shape = "cat", color = Color3.fromRGB(255, 120, 40), speed = 7, stamina = 5, luck = 4 },
	{ id = "Hibou", icon = "🦉", rarity = "Epic", egg = "Village", shape = "bird", color = Color3.fromRGB(150, 110, 80), speed = 6, stamina = 7, luck = 7 },
	{ id = "Licorne", icon = "🦄", rarity = "Legendary", egg = "Village", shape = "dog", color = Color3.fromRGB(255, 200, 255), speed = 9, stamina = 6, luck = 8 },
	-- Foret
	{ id = "Cerf", icon = "🦌", rarity = "Common", egg = "Foret", shape = "dog", color = Color3.fromRGB(170, 120, 70), speed = 6, stamina = 6, luck = 2 },
	{ id = "Loup", icon = "🐺", rarity = "Uncommon", egg = "Foret", shape = "dog", color = Color3.fromRGB(120, 120, 130), speed = 6, stamina = 9, luck = 3 },
	{ id = "Ours", icon = "🐻", rarity = "Rare", egg = "Foret", shape = "bear", color = Color3.fromRGB(120, 80, 50), speed = 3, stamina = 10, luck = 4 },
	{ id = "Panda", icon = "🐼", rarity = "Epic", egg = "Foret", shape = "bear", color = Color3.fromRGB(245, 245, 245), speed = 4, stamina = 8, luck = 8 },
	{ id = "Phenix", icon = "🐦‍🔥", rarity = "Legendary", egg = "Foret", shape = "bird", color = Color3.fromRGB(255, 90, 30), speed = 10, stamina = 7, luck = 6 },
	{ id = "Dragon", icon = "🐉", rarity = "Mythical", egg = "Foret", shape = "dragon", color = Color3.fromRGB(60, 200, 90), speed = 9, stamina = 10, luck = 7 },
	-- Desert
	{ id = "Scorpion", icon = "🦂", rarity = "Common", egg = "Desert", shape = "blob", color = Color3.fromRGB(150, 90, 40), speed = 4, stamina = 7, luck = 3 },
	{ id = "Chameau", icon = "🐫", rarity = "Uncommon", egg = "Desert", shape = "dog", color = Color3.fromRGB(220, 180, 110), speed = 4, stamina = 10, luck = 3 },
	{ id = "Cobra", icon = "🐍", rarity = "Rare", egg = "Desert", shape = "snake", color = Color3.fromRGB(90, 160, 60), speed = 8, stamina = 4, luck = 6 },
	{ id = "Lezard", icon = "🦎", rarity = "Epic", egg = "Desert", shape = "snake", color = Color3.fromRGB(120, 220, 120), speed = 9, stamina = 5, luck = 7 },
	{ id = "Sphinx", icon = "🦁", rarity = "Legendary", egg = "Desert", shape = "cat", color = Color3.fromRGB(230, 190, 90), speed = 8, stamina = 9, luck = 8 },
	{ id = "Genie", icon = "🧞", rarity = "Mythical", egg = "Desert", shape = "blob", color = Color3.fromRGB(90, 120, 255), speed = 10, stamina = 8, luck = 10 },
	{ id = "Pharaon", icon = "👑", rarity = "Secret", egg = "Desert", shape = "cat", color = Color3.fromRGB(255, 220, 90), speed = 10, stamina = 10, luck = 10 },
}
Config.PetById = {}
for _, pet in ipairs(Config.Pets) do
	Config.PetById[pet.id] = pet
end

-- Oeufs (un par zone)
Config.Eggs = {
	{ id = "Village", name = "Oeuf du Village", icon = "🥚", price = 50, zone = "Village", color = Color3.fromRGB(240, 240, 255) },
	{ id = "Foret", name = "Oeuf de la Foret", icon = "🌳", price = 600, zone = "Foret", color = Color3.fromRGB(120, 220, 110) },
	{ id = "Desert", name = "Oeuf du Desert", icon = "🏜️", price = 6000, zone = "Desert", color = Color3.fromRGB(255, 200, 100) },
}
Config.EggById = {}
for _, egg in ipairs(Config.Eggs) do
	Config.EggById[egg.id] = egg
end

-- Zones
Config.Zones = {
	{ id = "Village", name = "Starter Village", icon = "🏡", price = 0, center = Vector3.new(0, 0, 0), size = 220, coinValue = 5, coinCount = 40, ground = Color3.fromRGB(110, 200, 90), chestValue = 400 },
	{ id = "Foret", name = "Forest", icon = "🌲", price = 2500, center = Vector3.new(0, 0, -300), size = 220, coinValue = 30, coinCount = 40, ground = Color3.fromRGB(60, 150, 70), chestValue = 3000 },
	{ id = "Desert", name = "Desert", icon = "🏜️", price = 25000, center = Vector3.new(0, 0, -600), size = 220, coinValue = 150, coinCount = 40, ground = Color3.fromRGB(230, 200, 130), chestValue = 20000 },
}
Config.ZoneById = {}
for _, zone in ipairs(Config.Zones) do
	Config.ZoneById[zone.id] = zone
end

Config.Collect = {
	BaseRadius = 7, -- rayon de collecte sans pet
	RadiusPerPet = 2.5,
	Tick = 0.4,
	CoinRespawn = 6,
	ChestInterval = { 120, 200 },
	ChestLifetime = 60,
}

-- Objets a casser avec ses pets (cliquer dessus : les pets attaquent, l'objet explose en coins)
Config.Breakables = {
	PerZone = 10,
	Tick = 0.5, -- degats appliques toutes les 0,5 s
	PlayerDamage = 2, -- degats du joueur seul
	PetBaseDamage = 3, -- par pet equipe
	PetPowerDamage = 2, -- x puissance du pet
	MaxDistance = 90, -- le joueur doit rester proche
	Respawn = { 8, 16 },
	Types = {
		{ id = "Piggy", name = "Tirelire", hp = 60, reward = 12, weight = 55 },
		{ id = "Crystal", name = "Cristal", hp = 160, reward = 32, weight = 32 },
		{ id = "Gift", name = "Cadeau geant", hp = 450, reward = 95, weight = 13 },
	},
	-- multiplicateur de PV / gains par zone
	ZoneMult = { Village = 1, Foret = 6, Desert = 30 },
}

Config.Daily = {
	Cooldown = 20 * 3600,
	Coins = 500,
}

-- Courses
Config.Race = {
	LobbyTime = 25,
	Countdown = 3,
	MaxRacers = 4,
	Types = {
		{ id = "Sprint", name = "Sprint", icon = "⚡", laps = 1, reward = 250, description = "1 tour : la vitesse compte le plus" },
		{ id = "Marathon", name = "Marathon", icon = "🛡️", laps = 3, reward = 900, description = "3 tours : l'endurance fait la difference" },
	},
	AINames = { "Robo-Chat", "Turbo-Chien", "Lapinou", "Mister Renard" },
}

Config.Map = {
	SpawnPosition = Vector3.new(0, 3, 70),
	KillHeight = -40,
}

return Config
