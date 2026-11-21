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
	{ id = "Grimoire", img = "Village1", name = "Grimoire etoile", world = "Village", rarity = "Common", shape = "tome", c1 = R(60, 55, 62), c2 = R(255, 200, 70) },
	{ id = "PotionAmethyste", img = "Village2", name = "Potion d'amethyste", world = "Village", rarity = "Uncommon", shape = "flask", c1 = R(150, 80, 235), c2 = R(255, 200, 80) },
	{ id = "GlandOr", img = "Village3", name = "Gland d'or", world = "Village", rarity = "Rare", shape = "acorn", c1 = R(225, 165, 55), c2 = R(245, 205, 95) },
	{ id = "LanterneAncienne", img = "Village4", name = "Lanterne ancienne", world = "Village", rarity = "Epic", shape = "lantern", c1 = R(70, 60, 58), c2 = R(255, 150, 50) },
	{ id = "CouronneRoyale", img = "Village5", name = "Couronne royale", world = "Village", rarity = "Legendary", shape = "crown", c1 = R(255, 190, 60), c2 = R(210, 50, 55) },
	{ id = "EtoileCristal", img = "Village6", name = "Etoile de cristal", world = "Village", rarity = "Mythic", shape = "star8", c1 = R(60, 150, 255), c2 = R(210, 235, 255) },
	-- Enchanted Forest
	{ id = "OrbeSylvestre", img = "Forest1", name = "Orbe sylvestre", world = "Forest", rarity = "Common", shape = "cageorb", c1 = R(125, 50, 165), c2 = R(230, 170, 60) },
	{ id = "ChampignonLunaire", img = "Forest2", name = "Champignon lunaire", world = "Forest", rarity = "Uncommon", shape = "mushroom", c1 = R(90, 150, 255), c2 = R(230, 200, 170) },
	{ id = "PlumeEnchantee", img = "Forest3", name = "Plume enchantee", world = "Forest", rarity = "Rare", shape = "feather", c1 = R(150, 100, 205), c2 = R(230, 170, 60) },
	{ id = "CroissantMystique", img = "Forest4", name = "Croissant mystique", world = "Forest", rarity = "Epic", shape = "moon", c1 = R(130, 70, 185), c2 = R(230, 170, 60) },
	{ id = "CarillonFees", img = "Forest5", name = "Carillon des fees", world = "Forest", rarity = "Legendary", shape = "chime", c1 = R(90, 180, 255), c2 = R(200, 150, 60) },
	{ id = "EmblemeAile", img = "Forest6", name = "Embleme aile", world = "Forest", rarity = "Mythic", shape = "wings", c1 = R(150, 60, 220), c2 = R(245, 240, 230) },
	-- Crystal Cave
	{ id = "PierreRune", img = "Cave1", name = "Pierre de rune", world = "Cave", rarity = "Common", shape = "monolith", c1 = R(85, 85, 95), c2 = R(80, 220, 255) },
	{ id = "OrbeGalactique", img = "Cave2", name = "Orbe galactique", world = "Cave", rarity = "Uncommon", shape = "cageorb", c1 = R(40, 90, 220), c2 = R(220, 160, 60) },
	{ id = "CouronneCristal", img = "Cave3", name = "Couronne de cristal", world = "Cave", rarity = "Rare", shape = "crystalcrown", c1 = R(80, 170, 255), c2 = R(210, 240, 255) },
	{ id = "ToupieCristal", img = "Cave4", name = "Toupie de cristal", world = "Cave", rarity = "Epic", shape = "top", c1 = R(110, 150, 170), c2 = R(220, 160, 60) },
	{ id = "BlasonAmethyste", img = "Cave5", name = "Blason d'amethyste", world = "Cave", rarity = "Legendary", shape = "shield", c1 = R(120, 80, 150), c2 = R(220, 165, 60) },
	{ id = "AnneauRoyal", img = "Cave6", name = "Anneau royal", world = "Cave", rarity = "Mythic", shape = "ring", c1 = R(225, 165, 60), c2 = R(160, 60, 220) },
	{ id = "Oubliee", name = "Relique oubliee", world = "Cave", rarity = "Secret", shape = "cube", c1 = R(25, 15, 40), c2 = R(200, 120, 255), secret = true },
	-- Desert Kingdom
	{ id = "AnkhOr", img = "Desert1", name = "Ankh d'or", world = "Desert", rarity = "Common", shape = "ankh", c1 = R(240, 185, 60), c2 = R(60, 200, 230) },
	{ id = "ParcheminSolaire", img = "Desert2", name = "Parchemin solaire", world = "Desert", rarity = "Uncommon", shape = "scroll", c1 = R(240, 225, 190), c2 = R(230, 170, 60) },
	{ id = "CalicePharaon", img = "Desert3", name = "Calice du pharaon", world = "Desert", rarity = "Rare", shape = "chalice", c1 = R(230, 170, 60), c2 = R(150, 60, 210) },
	{ id = "SablierTemps", img = "Desert4", name = "Sablier du temps", world = "Desert", rarity = "Epic", shape = "hourglass", c1 = R(215, 160, 70), c2 = R(240, 200, 130) },
	{ id = "EtendardDesert", img = "Desert5", name = "Etendard du desert", world = "Desert", rarity = "Legendary", shape = "banner", c1 = R(240, 130, 40), c2 = R(220, 160, 60) },
	{ id = "SoleilOr", img = "Desert6", name = "Soleil d'or", world = "Desert", rarity = "Mythic", shape = "sun", c1 = R(255, 185, 40), c2 = R(255, 240, 180) },
	-- Frozen World
	{ id = "FloconEternel", img = "Frozen1", name = "Flocon eternel", world = "Frozen", rarity = "Common", shape = "snowflake", c1 = R(120, 200, 255), c2 = R(240, 250, 255) },
	{ id = "ClocheGivre", img = "Frozen2", name = "Cloche de givre", world = "Frozen", rarity = "Uncommon", shape = "bell", c1 = R(150, 180, 240), c2 = R(110, 220, 255) },
	{ id = "CouronneGlace", img = "Frozen3", name = "Couronne de glace", world = "Frozen", rarity = "Rare", shape = "crystalcrown", c1 = R(90, 165, 255), c2 = R(230, 245, 255) },
	{ id = "ChrysalideGlace", img = "Frozen4", name = "Chrysalide de glace", world = "Frozen", rarity = "Epic", shape = "cocoon", c1 = R(80, 120, 230), c2 = R(160, 205, 255) },
	{ id = "OrbeBoreal", img = "Frozen5", name = "Orbe boreal", world = "Frozen", rarity = "Legendary", shape = "cageorb", c1 = R(40, 110, 225), c2 = R(220, 160, 60) },
	{ id = "EmblemeArgent", img = "Frozen6", name = "Embleme d'argent", world = "Frozen", rarity = "Mythic", shape = "wings", c1 = R(40, 40, 60), c2 = R(225, 225, 235) },
	-- Lava World
	{ id = "OursinMagma", img = "Lava1", name = "Oursin de magma", world = "Lava", rarity = "Uncommon", shape = "spiky", c1 = R(120, 45, 30), c2 = R(255, 120, 40) },
	{ id = "CouronneBraise", img = "Lava2", name = "Couronne de braise", world = "Lava", rarity = "Rare", shape = "crown", c1 = R(205, 85, 35), c2 = R(255, 190, 70) },
	{ id = "EclipseNoire", img = "Lava3", name = "Eclipse noire", world = "Lava", rarity = "Epic", shape = "eclipse", c1 = R(12, 10, 12), c2 = R(255, 120, 30) },
	{ id = "CoeurLave", img = "Lava4", name = "Coeur de lave", world = "Lava", rarity = "Legendary", shape = "heart", c1 = R(220, 45, 30), c2 = R(70, 35, 35) },
	{ id = "CouronneVolcan", img = "Lava5", name = "Couronne volcanique", world = "Lava", rarity = "Mythic", shape = "crown", c1 = R(95, 45, 35), c2 = R(255, 120, 40) },
	{ id = "AnneauFeu", img = "Lava6", name = "Anneau de feu", world = "Lava", rarity = "Celestial", shape = "ring", c1 = R(255, 95, 30), c2 = R(255, 210, 90) },
	-- Celestial World
	{ id = "MedaillonCeleste", img = "Celestial1", name = "Medaillon celeste", world = "Celestial", rarity = "Rare", shape = "amulet", c1 = R(230, 170, 60), c2 = R(150, 60, 220) },
	{ id = "EtoileAstrale", img = "Celestial2", name = "Etoile astrale", world = "Celestial", rarity = "Epic", shape = "star8", c1 = R(255, 200, 80), c2 = R(80, 210, 255) },
	{ id = "OrbeCosmos", img = "Celestial3", name = "Orbe du cosmos", world = "Celestial", rarity = "Legendary", shape = "cageorb", c1 = R(140, 60, 225), c2 = R(230, 170, 60) },
	{ id = "CaliceCeleste", img = "Celestial4", name = "Calice celeste", world = "Celestial", rarity = "Mythic", shape = "chalice", c1 = R(235, 175, 60), c2 = R(150, 60, 220) },
	{ id = "CouronneCieux", img = "Celestial5", name = "Couronne des cieux", world = "Celestial", rarity = "Celestial", shape = "crown", c1 = R(250, 200, 70), c2 = R(60, 170, 255) },
	{ id = "OrbeInfini", img = "Celestial6", name = "Orbe infini", world = "Celestial", rarity = "Divine", shape = "cageorb", c1 = R(70, 60, 225), c2 = R(235, 175, 60) },
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
	Village = { name = "Caisse du Village", price = 100, odds = { Common = 58, Uncommon = 28, Rare = 10, Epic = 3.3, Legendary = 0.65, Mythic = 0.05 } },
	Forest = { name = "Caisse sylvestre", price = 700, odds = { Common = 50, Uncommon = 30, Rare = 14, Epic = 4.8, Legendary = 1.1, Mythic = 0.1 } },
	Cave = { name = "Caisse de cristal", price = 4000, odds = { Common = 46, Uncommon = 30, Rare = 16, Epic = 6.2, Legendary = 1.6, Mythic = 0.2, Secret = 0.0005 } },
	Desert = { name = "Caisse royale", price = 25000, odds = { Common = 45, Uncommon = 30, Rare = 16, Epic = 6.5, Legendary = 2.2, Mythic = 0.3 } },
	Frozen = { name = "Caisse de givre", price = 150000, odds = { Common = 44, Uncommon = 30, Rare = 16, Epic = 7, Legendary = 2.6, Mythic = 0.4 } },
	Lava = { name = "Caisse volcanique", price = 900000, odds = { Uncommon = 60, Rare = 25, Epic = 10, Legendary = 4, Mythic = 0.9, Celestial = 0.1 } },
	Celestial = { name = "Caisse celeste", price = 6000000, odds = { Rare = 62, Epic = 26, Legendary = 9, Mythic = 2.5, Celestial = 0.45, Divine = 0.05, Secret = 0.0002 } },
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
	{ id = "m12", text = "Decouvre 35 reliques differentes", stat = "Discovered", goal = 35, coins = 20000000 },
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
