-- RELIC RUSH : configuration centrale. Tout l'equilibrage du jeu se regle ici.

local Config = {}
Config.Version = "1.0"

Config.Colors = {
	Gold = Color3.fromRGB(255, 200, 60),
	Navy = Color3.fromRGB(16, 20, 48),
	Purple = Color3.fromRGB(120, 60, 210),
}

-- Raretes ----------------------------------------------------------------------------------------
Config.Rarities = {
	{ id = "Common", name = "Commune", color = Color3.fromRGB(200, 205, 215), mult = 1 },
	{ id = "Uncommon", name = "Peu commune", color = Color3.fromRGB(110, 225, 110), mult = 2 },
	{ id = "Rare", name = "Rare", color = Color3.fromRGB(70, 160, 255), mult = 4 },
	{ id = "Epic", name = "Epique", color = Color3.fromRGB(180, 90, 255), mult = 9 },
	{ id = "Legendary", name = "Legendaire", color = Color3.fromRGB(255, 190, 40), mult = 20 },
	{ id = "Mythic", name = "Mythique", color = Color3.fromRGB(255, 70, 90), mult = 50 },
	{ id = "Celestial", name = "Celeste", color = Color3.fromRGB(90, 235, 255), mult = 130 },
	{ id = "Divine", name = "Divine", color = Color3.fromRGB(255, 245, 190), mult = 350 },
	{ id = "Secret", name = "Secrete", color = Color3.fromRGB(30, 20, 40), mult = 1000 },
}
Config.RarityById = {}
for i, r in ipairs(Config.Rarities) do
	r.index = i
	Config.RarityById[r.id] = r
end

-- Mondes -----------------------------------------------------------------------------------------
-- mult : multiplicateur des tresors, des reliques et du boss du monde
Config.Worlds = {
	{ id = "Village", name = "Starter Village", price = 0, mult = 1, center = Vector3.new(0, 0, 0), size = 340, color = Color3.fromRGB(120, 210, 90) },
	{ id = "Forest", name = "Enchanted Forest", price = 2500, mult = 6, center = Vector3.new(1200, 0, 0), size = 320, color = Color3.fromRGB(70, 170, 90) },
	{ id = "Cave", name = "Crystal Cave", price = 60000, mult = 35, center = Vector3.new(2400, 0, 0), size = 320, color = Color3.fromRGB(110, 90, 220) },
	{ id = "Desert", name = "Desert Kingdom", price = 1500000, mult = 200, center = Vector3.new(3600, 0, 0), size = 320, color = Color3.fromRGB(240, 200, 120) },
	{ id = "Frozen", name = "Frozen World", price = 40000000, mult = 1200, center = Vector3.new(4800, 0, 0), size = 320, color = Color3.fromRGB(170, 220, 255) },
	{ id = "Lava", name = "Lava World", price = 1.2e9, mult = 7000, center = Vector3.new(6000, 0, 0), size = 320, color = Color3.fromRGB(255, 100, 40) },
	{ id = "Celestial", name = "Celestial World", price = 4e10, mult = 40000, center = Vector3.new(7200, 0, 0), size = 320, color = Color3.fromRGB(255, 235, 160) },
}
Config.WorldById = {}
for i, w in ipairs(Config.Worlds) do
	w.index = i
	Config.WorldById[w.id] = w
end

-- Reliques ---------------------------------------------------------------------------------------
-- shape : forme du modele 3D (voir RelicModel). c1/c2 : couleurs principale / secondaire.
local R = Color3.fromRGB
Config.Relics = {
	-- Starter Village
	{ id = "LivreEtoile", img = "Village1", name = "Livre etoile", world = "Village", rarity = "Common", shape = "tome", c1 = R(50, 100, 200), c2 = R(255, 200, 70) },
	{ id = "FioleAzur", img = "Village2", name = "Fiole d'azur", world = "Village", rarity = "Uncommon", shape = "flask", c1 = R(80, 200, 235), c2 = R(230, 240, 255) },
	{ id = "CouronneRoyale", img = "Village3", name = "Couronne royale", world = "Village", rarity = "Rare", shape = "crown", c1 = R(255, 195, 60), c2 = R(60, 140, 255) },
	-- Enchanted Forest
	{ id = "GlandAncien", img = "Forest1", name = "Gland ancien", world = "Forest", rarity = "Common", shape = "acorn", c1 = R(215, 120, 45), c2 = R(110, 170, 70) },
	{ id = "Amanite", img = "Forest2", name = "Amanite enchantee", world = "Forest", rarity = "Uncommon", shape = "toadstool", c1 = R(215, 50, 45), c2 = R(245, 235, 215) },
	{ id = "LanterneMousse", img = "Forest3", name = "Lanterne moussue", world = "Forest", rarity = "Rare", shape = "lantern", c1 = R(85, 80, 70), c2 = R(255, 180, 60) },
	-- Crystal Cave
	{ id = "Amethyste", img = "Cave1", name = "Amas d'amethyste", world = "Cave", rarity = "Uncommon", shape = "cluster", c1 = R(160, 80, 240), c2 = R(110, 105, 110) },
	{ id = "PiocheCristal", img = "Cave2", name = "Pioche de cristal", world = "Cave", rarity = "Rare", shape = "pickaxe", c1 = R(150, 150, 165), c2 = R(170, 80, 240) },
	{ id = "LanterneCristal", img = "Cave3", name = "Lanterne de cristal", world = "Cave", rarity = "Epic", shape = "lantern", c1 = R(80, 80, 90), c2 = R(180, 90, 255) },
	{ id = "Oubliee", name = "Relique oubliee", world = "Cave", rarity = "Secret", shape = "cube", c1 = R(25, 15, 40), c2 = R(200, 120, 255), secret = true },
	-- Desert Kingdom
	{ id = "SablierOr", img = "Desert1", name = "Sablier d'or", world = "Desert", rarity = "Rare", shape = "hourglass", c1 = R(220, 160, 60), c2 = R(245, 205, 130) },
	{ id = "AnkhOr", img = "Desert2", name = "Ankh d'or", world = "Desert", rarity = "Epic", shape = "ankh", c1 = R(240, 185, 60), c2 = R(60, 160, 240) },
	{ id = "ScarabeeAile", img = "Desert3", name = "Scarabee aile", world = "Desert", rarity = "Legendary", shape = "scarab", c1 = R(240, 180, 50), c2 = R(60, 150, 240) },
	-- Frozen World
	{ id = "FloconEternel", img = "Frozen1", name = "Flocon eternel", world = "Frozen", rarity = "Epic", shape = "snowflake", c1 = R(110, 195, 255), c2 = R(235, 248, 255) },
	{ id = "ClocheGivre", img = "Frozen2", name = "Cloche de givre", world = "Frozen", rarity = "Legendary", shape = "bell", c1 = R(150, 175, 215), c2 = R(90, 200, 255) },
	{ id = "CouronneGlace", img = "Frozen3", name = "Couronne de glace", world = "Frozen", rarity = "Mythic", shape = "crystalcrown", c1 = R(120, 190, 255), c2 = R(230, 245, 255) },
	-- Lava World
	{ id = "RocheMagma", img = "Lava1", name = "Roche de magma", world = "Lava", rarity = "Legendary", shape = "cluster", c1 = R(255, 140, 40), c2 = R(70, 50, 45) },
	{ id = "CouronneVolcan", img = "Lava2", name = "Couronne volcanique", world = "Lava", rarity = "Mythic", shape = "crown", c1 = R(75, 55, 50), c2 = R(255, 130, 40) },
	{ id = "MarteauForge", img = "Lava3", name = "Marteau de forge", world = "Lava", rarity = "Celestial", shape = "hammer", c1 = R(100, 90, 95), c2 = R(255, 140, 40) },
	-- Celestial World
	{ id = "PlaneteCeleste", img = "Celestial1", name = "Planete celeste", world = "Celestial", rarity = "Mythic", shape = "planet", c1 = R(110, 60, 220), c2 = R(240, 185, 60) },
	{ id = "LuneEtoilee", img = "Celestial2", name = "Lune etoilee", world = "Celestial", rarity = "Celestial", shape = "moon", c1 = R(130, 80, 230), c2 = R(245, 190, 60) },
	{ id = "SoleilCosmique", img = "Celestial3", name = "Soleil cosmique", world = "Celestial", rarity = "Divine", shape = "sun", c1 = R(245, 185, 50), c2 = R(150, 90, 255) },
	{ id = "Neant", name = "Coeur du neant", world = "Celestial", rarity = "Secret", shape = "heart", c1 = R(20, 10, 30), c2 = R(160, 80, 255), secret = true },
	-- Reliques de boss (une par monde)
	{ id = "BossGolem", name = "Noyau de golem", world = "Village", rarity = "Epic", shape = "golem", c1 = R(140, 130, 150), c2 = R(200, 90, 255), boss = true },
	{ id = "BossSylve", name = "Ecorce du gardien", world = "Forest", rarity = "Legendary", shape = "golem", c1 = R(110, 80, 50), c2 = R(110, 255, 150), boss = true },
	{ id = "BossCristal", name = "Coeur du colosse", world = "Cave", rarity = "Legendary", shape = "golem", c1 = R(150, 120, 230), c2 = R(110, 240, 255), boss = true },
	{ id = "BossPharaon", name = "Sceau du pharaon", world = "Desert", rarity = "Mythic", shape = "golem", c1 = R(230, 190, 90), c2 = R(60, 120, 230), boss = true },
	{ id = "BossYeti", name = "Givre du titan", world = "Frozen", rarity = "Mythic", shape = "golem", c1 = R(220, 235, 255), c2 = R(90, 170, 255), boss = true },
	{ id = "BossMagma", name = "Ame du volcan", world = "Lava", rarity = "Celestial", shape = "golem", c1 = R(70, 50, 50), c2 = R(255, 110, 30), boss = true },
	{ id = "BossAstral", name = "Couronne astrale", world = "Celestial", rarity = "Divine", shape = "golem", c1 = R(250, 245, 220), c2 = R(120, 220, 255), boss = true },
}
Config.RelicById = {}
for i, r in ipairs(Config.Relics) do
	r.order = i
	local w = Config.WorldById[r.world]
	local rar = Config.RarityById[r.rarity]
	-- puissance : rarete x monde, legere variation par relique pour que chacune soit unique
	r.power = math.floor(rar.mult * w.mult * (0.92 + ((i * 37) % 17) / 100) * 10 + 0.5)
	Config.RelicById[r.id] = r
end

-- Caisses (une par monde) : chances par rarete (en %), cout
Config.Crates = {
	Village = { name = "Caisse du Village", price = 100, odds = { Common = 72, Uncommon = 24, Rare = 4 } },
	Forest = { name = "Caisse sylvestre", price = 700, odds = { Common = 68, Uncommon = 26, Rare = 6 } },
	Cave = { name = "Caisse de cristal", price = 4000, odds = { Uncommon = 70, Rare = 25, Epic = 5, Secret = 0.0005 } },
	Desert = { name = "Caisse royale", price = 25000, odds = { Rare = 72, Epic = 24, Legendary = 4 } },
	Frozen = { name = "Caisse de givre", price = 150000, odds = { Epic = 74, Legendary = 23, Mythic = 3 } },
	Lava = { name = "Caisse volcanique", price = 900000, odds = { Legendary = 76, Mythic = 22, Celestial = 2 } },
	Celestial = { name = "Caisse celeste", price = 6000000, odds = { Mythic = 78, Celestial = 20.5, Divine = 1.5, Secret = 0.0002 } },
}

-- Tresors (objets a detruire) : par monde, 3 tailles. hp et coins x mult du monde
Config.Treasures = {
	{ id = "Vase", name = "Vase", hp = 30, coins = 6, weight = 55, scale = 1 },
	{ id = "Coffre", name = "Coffre", hp = 140, coins = 26, weight = 33, scale = 1.25 },
	{ id = "Tresor", name = "Tresor geant", hp = 700, coins = 140, weight = 12, scale = 1.8 },
}
Config.TreasurePerWorld = 26
Config.TreasureRespawn = { 6, 12 }
Config.HitInterval = 0.35 -- secondes entre deux coups des reliques
Config.BaseDamage = 4 -- degats du joueur sans relique
Config.MaxTargetDistance = 120
Config.CoinPickupRadius = 14 -- + amelioration

-- Ameliorations (pieces) ----------------------------------------------------------------------------
Config.Upgrades = {
	{ id = "Power", name = "Puissance", desc = "+15 % de puissance", base = 150, growth = 1.55, max = 60, per = 0.15 },
	{ id = "Coins", name = "Fortune", desc = "+10 % de pieces", base = 220, growth = 1.6, max = 50, per = 0.10 },
	{ id = "Luck", name = "Chance", desc = "+6 % de chance de rarete", base = 350, growth = 1.75, max = 25, per = 0.06 },
	{ id = "Speed", name = "Vitesse", desc = "+1 vitesse de course", base = 120, growth = 1.5, max = 16, per = 1 },
	{ id = "Magnet", name = "Aimant", desc = "+3 de rayon de ramassage", base = 140, growth = 1.55, max = 12, per = 3 },
	{ id = "Slots", name = "Emplacements", desc = "+1 relique equipee", base = 1200, growth = 7, max = 6, per = 1, keepOnRebirth = true },
}
Config.BaseSlots = 3
Config.InventoryBase = 60

-- Boutique (pieces) : potions temporaires et avantages permanents
Config.Shop = {
	{ id = "PotionCoins", name = "Potion de fortune", desc = "Pieces x2 pendant 10 min", price = 800, kind = "potion", boost = "Coins", duration = 600, scale = true },
	{ id = "PotionLuck", name = "Potion de chance", desc = "Chance x2 pendant 10 min", price = 1200, kind = "potion", boost = "Luck", duration = 600, scale = true },
	{ id = "PotionPower", name = "Potion de force", desc = "Puissance x2 pendant 10 min", price = 1000, kind = "potion", boost = "Power", duration = 600, scale = true },
	{ id = "Bag", name = "Grand sac", desc = "+30 places d'inventaire", price = 5000, kind = "inventory", amount = 30, growth = 3 },
	{ id = "AutoHit", name = "Frappe automatique", desc = "Tes reliques attaquent seules le tresor le plus proche", price = 15000, kind = "perk" },
	{ id = "TripleOpen", name = "Ouverture x3", desc = "Ouvre 3 caisses d'un coup", price = 8000, kind = "perk" },
}

-- Renaissance (Rebirth) -------------------------------------------------------------------------------
Config.Rebirth = {
	BaseCost = 50000, Growth = 3.2,
	CoinBonus = 0.5, -- +50 % de pieces par renaissance
	PowerBonus = 0.25, -- +25 % de puissance par renaissance
}

-- Boss -----------------------------------------------------------------------------------------------
Config.Boss = {
	Village = { name = "Golem de pierre", hp = 12000, coins = 1500 },
	Forest = { name = "Gardien sylvestre", hp = 12000, coins = 1500 },
	Cave = { name = "Colosse de cristal", hp = 12000, coins = 1500 },
	Desert = { name = "Pharaon de sable", hp = 12000, coins = 1500 },
	Frozen = { name = "Titan de givre", hp = 12000, coins = 1500 },
	Lava = { name = "Seigneur du magma", hp = 12000, coins = 1500 },
	Celestial = { name = "Gardien astral", hp = 12000, coins = 1500 },
}
Config.BossRespawn = 150 -- secondes apres la defaite
Config.BossHpPerPlayer = 0.7 -- +70 % de PV par joueur present
Config.BossRelicChance = 0.12 -- chance d'obtenir la relique du boss (participants a plus de 5 %)
Config.BossShockwave = { Interval = 7, Radius = 40, Push = 70 }

-- Quetes -----------------------------------------------------------------------------------------------
Config.DailyQuestPool = {
	{ id = "break", text = "Detruis %d tresors", goal = 60, stat = "Breaks", reward = 2 },
	{ id = "crates", text = "Ouvre %d caisses", goal = 15, stat = "Crates", reward = 2 },
	{ id = "coins", text = "Recolte %s pieces", goal = 5000, stat = "CoinsEarned", reward = 2, worldScaled = true },
	{ id = "boss", text = "Inflige des degats a %d boss", goal = 2, stat = "BossFights", reward = 3 },
	{ id = "upgrade", text = "Achete %d ameliorations", goal = 5, stat = "Upgrades", reward = 2 },
	{ id = "rare", text = "Obtiens %d reliques Rare ou mieux", goal = 3, stat = "RarePlus", reward = 3 },
}
Config.DailyQuestCount = 3
Config.QuestRewardBase = 400 -- x reward x mult du meilleur monde
Config.Milestones = {
	{ id = "m1", text = "Ouvre ta premiere caisse", stat = "Crates", goal = 1, coins = 150 },
	{ id = "m2", text = "Detruis 50 tresors", stat = "Breaks", goal = 50, coins = 300 },
	{ id = "m3", text = "Equipe 3 reliques", stat = "Equipped", goal = 3, coins = 400 },
	{ id = "m4", text = "Debloque l'Enchanted Forest", stat = "Worlds", goal = 2, coins = 1500 },
	{ id = "m5", text = "Bats ton premier boss", stat = "BossWins", goal = 1, coins = 3000 },
	{ id = "m6", text = "Decouvre 15 reliques differentes", stat = "Discovered", goal = 15, coins = 8000 },
	{ id = "m7", text = "Fais ta premiere renaissance", stat = "Rebirths", goal = 1, coins = 20000 },
	{ id = "m8", text = "Debloque la Crystal Cave", stat = "Worlds", goal = 3, coins = 50000 },
	{ id = "m9", text = "Obtiens une relique Legendaire", stat = "Legendary", goal = 1, coins = 100000 },
	{ id = "m10", text = "Detruis 5 000 tresors", stat = "Breaks", goal = 5000, coins = 500000 },
	{ id = "m11", text = "Debloque le Desert Kingdom", stat = "Worlds", goal = 4, coins = 2000000 },
	{ id = "m12", text = "Decouvre 25 reliques differentes", stat = "Discovered", goal = 25, coins = 20000000 },
}

-- Recompenses quotidiennes (7 jours, x mult du meilleur monde pour les pieces)
Config.Daily = {
	Cooldown = 20 * 3600, Reset = 48 * 3600,
	Days = {
		{ coins = 300 }, { coins = 500 }, { potion = "PotionCoins" }, { coins = 1200 },
		{ potion = "PotionLuck" }, { coins = 3000 }, { crate = 3, coins = 5000 },
	},
}

-- Index : bonus permanent par monde complete
Config.IndexWorldBonus = 0.05 -- +5 % de puissance par monde dont toutes les reliques (hors secretes) sont decouvertes

Config.Trade = { MaxItems = 9, ConfirmTime = 4, RequestTimeout = 30 }

Config.SpawnOffset = Vector3.new(0, 4, 48)
Config.MusicId = "" -- ex. "rbxassetid://123456" (musique de fond, volume reglable dans Parametres)

return Config
