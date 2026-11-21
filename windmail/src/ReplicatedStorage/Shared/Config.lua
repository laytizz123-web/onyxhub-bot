-- WINDMAIL : configuration centrale (equilibrage, objets, zones, evenements).
-- Tout le reglage du jeu se fait ici : aucun chiffre "magique" dans les scripts.

local Config = {}

Config.Version = "0.1"

-- Rangs de facteur -----------------------------------------------------------------------
-- XP pour passer du niveau n au niveau n+1 : Base * n ^ Exponent
Config.Rank = { Base = 60, Exponent = 1.35, Max = 40 }
Config.RankTitles = {
	{ 1, "Apprenti facteur" }, { 3, "Facteur du port" }, { 6, "Coursier des falaises" },
	{ 10, "Messager celeste" }, { 15, "Pilote des tempetes" }, { 22, "Capitaine des vents" }, { 30, "Maitre des vents" },
}

-- Zones (deblocage par rang ; l'exploration reste libre, seules les livraisons sont limitees)
Config.Zones = {
	{ id = "Port", name = "Port-Brise", rank = 1, color = Color3.fromRGB(120, 190, 255), center = Vector3.new(0, 0, 0) },
	{ id = "Verger", name = "Le Verger", rank = 3, color = Color3.fromRGB(150, 215, 100), center = Vector3.new(330, 0, -120) },
	{ id = "Falaises", name = "Falaises Brumeuses", rank = 6, color = Color3.fromRGB(170, 180, 200), center = Vector3.new(-320, 0, -230) },
	{ id = "Marche", name = "Marche Celeste", rank = 10, color = Color3.fromRGB(255, 190, 90), center = Vector3.new(60, 0, -520) },
	{ id = "Pic", name = "Pic des Tempetes", rank = 15, color = Color3.fromRGB(190, 140, 255), center = Vector3.new(470, 0, -560) },
}
Config.ZoneById = {}
for i, z in ipairs(Config.Zones) do
	z.index = i
	Config.ZoneById[z.id] = z
end

-- Colis ----------------------------------------------------------------------------------
-- weight : probabilite relative ; rank : rang minimum ; pay : multiplicateur de recompense
Config.Parcels = {
	{ id = "Lettre", name = "Lettre", weight = 40, rank = 1, pay = 1.0, color = Color3.fromRGB(245, 235, 210), size = Vector3.new(1.6, 0.4, 1.1),
		desc = "Un courrier classique. Rapide et sans souci." },
	{ id = "Fragile", name = "Colis fragile", weight = 22, rank = 2, pay = 1.6, fragile = true, color = Color3.fromRGB(255, 170, 120), size = Vector3.new(1.8, 1.4, 1.8),
		desc = "Atterris en douceur : chaque choc l'abime." },
	{ id = "Express", name = "Express", weight = 18, rank = 4, pay = 2.0, express = true, color = Color3.fromRGB(255, 90, 90), size = Vector3.new(1.6, 1.2, 1.6),
		desc = "A livrer avant la fin du chrono !" },
	{ id = "Lourd", name = "Malle lourde", weight = 12, rank = 7, pay = 2.6, heavy = true, color = Color3.fromRGB(150, 110, 75), size = Vector3.new(2.4, 1.8, 1.8),
		desc = "Tu planes moins bien... sauf si un ami vole a tes cotes." },
	{ id = "Mystere", name = "Colis mystere", weight = 8, rank = 3, pay = 1.4, mystery = true, color = Color3.fromRGB(170, 120, 255), size = Vector3.new(1.6, 1.6, 1.6),
		desc = "Contient un timbre de collection au hasard." },
}
Config.ParcelById = {}
for _, p in ipairs(Config.Parcels) do
	Config.ParcelById[p.id] = p
end

Config.Delivery = {
	BaseCoins = 12, -- recompense de base
	CoinsPerStud = 0.09, -- + distance entre la poste et la boite aux lettres
	XPPerCoin = 0.6,
	ParSpeed = 38, -- vitesse de reference (studs/s) pour le temps "par"
	ParBonus = 18, -- secondes ajoutees au temps par
	ExpressFactor = 1.25, -- chrono express = par * facteur
	Grades = { -- ratio temps / par -> note et multiplicateur
		{ max = 0.65, grade = "S", mult = 1.6, color = Color3.fromRGB(255, 210, 60) },
		{ max = 0.9, grade = "A", mult = 1.3, color = Color3.fromRGB(110, 230, 140) },
		{ max = 1.25, grade = "B", mult = 1.1, color = Color3.fromRGB(120, 190, 255) },
		{ max = math.huge, grade = "C", mult = 1.0, color = Color3.fromRGB(200, 200, 210) },
	},
	ImpactSpeed = 55, -- perte de vitesse brutale (studs/s) consideree comme un choc
	ImpactDamage = 0.25, -- integrite perdue par choc (colis fragile)
	SplashDamage = 0.5, -- chute dans la mer
	ConvoyRadius = 40, -- un autre facteur a moins de 40 studs = convoi
	ConvoyBonus = 0.3, -- +30 % pour le livreur
	ConvoyAssist = 0.2, -- 20 % de la recompense offerts aux equipiers proches
	HeavyConvoySink = 1.0, -- malle lourde en convoi : plane normalement
}

-- Planeurs (achetables avec les pieces gagnees en jeu ; aucun avantage payant) --------------
-- cruise/max : vitesse de croisiere / max ; sink : chute (studs/s) ; stamina : reserve de boost (s)
Config.Gliders = {
	{ id = "Lin", name = "Toile de lin", price = 0, rank = 1, cruise = 34, max = 70, sink = 9, stamina = 3, color = Color3.fromRGB(235, 225, 200), accent = Color3.fromRGB(150, 110, 70) },
	{ id = "Mouette", name = "Aile de mouette", price = 900, rank = 3, cruise = 40, max = 80, sink = 7.5, stamina = 4, color = Color3.fromRGB(250, 250, 255), accent = Color3.fromRGB(120, 140, 170) },
	{ id = "Voilure", name = "Voilure marine", price = 4500, rank = 6, cruise = 46, max = 92, sink = 6.5, stamina = 5, color = Color3.fromRGB(70, 130, 210), accent = Color3.fromRGB(245, 245, 250) },
	{ id = "Aigle", name = "Plume d'aigle", price = 18000, rank = 11, cruise = 52, max = 105, sink = 5.5, stamina = 6, color = Color3.fromRGB(140, 95, 55), accent = Color3.fromRGB(240, 220, 170) },
	{ id = "Aurore", name = "Aile d'aurore", price = 65000, rank = 18, cruise = 60, max = 120, sink = 4.5, stamina = 8, color = Color3.fromRGB(120, 230, 210), accent = Color3.fromRGB(200, 120, 255) },
}
Config.GliderById = {}
for i, g in ipairs(Config.Gliders) do
	g.index = i
	Config.GliderById[g.id] = g
end

-- Sacoches : nombre de colis transportes en meme temps (= tournees plus rentables)
Config.Satchels = {
	{ level = 1, name = "Besace", capacity = 1, price = 0 },
	{ level = 2, name = "Sacoche en cuir", capacity = 2, price = 600, rank = 2 },
	{ level = 3, name = "Sacoche double", capacity = 3, price = 3500, rank = 5 },
	{ level = 4, name = "Sac de tournee", capacity = 4, price = 14000, rank = 9 },
	{ level = 5, name = "Sac du maitre", capacity = 5, price = 50000, rank = 14 },
}

-- Trainees (cosmetiques) : pieces ou timbres
Config.Trails = {
	{ id = "Aucune", name = "Aucune", price = 0 },
	{ id = "Brise", name = "Brise", price = 1500, color = Color3.fromRGB(230, 245, 255) },
	{ id = "Corail", name = "Corail", price = 6000, color = Color3.fromRGB(255, 130, 110) },
	{ id = "Emeraude", name = "Emeraude", price = 20000, color = Color3.fromRGB(80, 220, 140) },
	{ id = "Aurore", name = "Aurore boreale", stampSet = "Secrets", color = Color3.fromRGB(150, 120, 255), color2 = Color3.fromRGB(90, 240, 220) },
}
Config.TrailById = {}
for _, t in ipairs(Config.Trails) do
	Config.TrailById[t.id] = t
end

-- Timbres de collection ------------------------------------------------------------------
-- source : mystery (colis mystere), secret (cache sur la carte), event (evenement)
Config.Stamps = {
	{ id = "Phare", name = "Le Phare", set = "Port", rarity = "Commun", source = "mystery" },
	{ id = "Mouette", name = "La Mouette", set = "Port", rarity = "Commun", source = "mystery" },
	{ id = "Ancre", name = "L'Ancre", set = "Port", rarity = "Rare", source = "mystery" },
	{ id = "Pomme", name = "La Pomme d'or", set = "Verger", rarity = "Commun", source = "mystery" },
	{ id = "Moulin", name = "Le Moulin", set = "Verger", rarity = "Commun", source = "mystery" },
	{ id = "Ruche", name = "La Ruche", set = "Verger", rarity = "Rare", source = "mystery" },
	{ id = "Brume", name = "La Brume", set = "Falaises", rarity = "Commun", source = "mystery" },
	{ id = "Corbeau", name = "Le Corbeau", set = "Falaises", rarity = "Rare", source = "mystery" },
	{ id = "Lanterne", name = "La Lanterne", set = "Marche", rarity = "Rare", source = "mystery" },
	{ id = "Eclair", name = "L'Eclair", set = "Pic", rarity = "Epique", source = "mystery" },
	{ id = "Grotte", name = "La Grotte cachee", set = "Secrets", rarity = "Secret", source = "secret" },
	{ id = "Sommet", name = "Le Sommet du phare", set = "Secrets", rarity = "Secret", source = "secret" },
	{ id = "Ilot", name = "L'Ilot oublie", set = "Secrets", rarity = "Secret", source = "secret" },
	{ id = "Epave", name = "L'Epave", set = "Secrets", rarity = "Secret", source = "secret" },
	{ id = "Ballon", name = "Le Ballon egare", set = "Evenements", rarity = "Legendaire", source = "event" },
	{ id = "Tournee", name = "La Grande Tournee", set = "Evenements", rarity = "Epique", source = "event" },
}
Config.StampById = {}
for _, s in ipairs(Config.Stamps) do
	Config.StampById[s.id] = s
end
Config.StampRarity = {
	Commun = { weight = 60, color = Color3.fromRGB(200, 205, 215) },
	Rare = { weight = 28, color = Color3.fromRGB(90, 170, 255) },
	Epique = { weight = 10, color = Color3.fromRGB(190, 110, 255) },
	Legendaire = { weight = 0, color = Color3.fromRGB(255, 200, 60) },
	Secret = { weight = 0, color = Color3.fromRGB(80, 230, 190) },
}
-- Bonus de collection : completer un set donne un bonus permanent
Config.StampSets = {
	{ id = "Port", name = "Port-Brise", bonus = "+5 % de pieces", coinBonus = 0.05 },
	{ id = "Verger", name = "Le Verger", bonus = "+5 % de pieces", coinBonus = 0.05 },
	{ id = "Falaises", name = "Falaises", bonus = "+10 % d'XP", xpBonus = 0.1 },
	{ id = "Marche", name = "Marche", bonus = "+5 % de pieces", coinBonus = 0.05 },
	{ id = "Pic", name = "Pic", bonus = "+10 % d'XP", xpBonus = 0.1 },
	{ id = "Secrets", name = "Secrets", bonus = "Trainee Aurore boreale", trail = "Aurore" },
	{ id = "Evenements", name = "Evenements", bonus = "+10 % de pieces", coinBonus = 0.1 },
}

-- Recompense quotidienne (serie de jours)
Config.Daily = { Cooldown = 20 * 3600, Reset = 48 * 3600, Coins = { 150, 250, 400, 600, 900, 1300, 2000 } }

-- Evenements aleatoires --------------------------------------------------------------------
Config.Events = {
	Interval = { 300, 480 }, -- secondes entre deux evenements
	List = {
		{ id = "VentDore", name = "Vent dore", duration = 150, desc = "Toutes les livraisons rapportent x2 !", color = Color3.fromRGB(255, 205, 70) },
		{ id = "Ballon", name = "Ballon egare", duration = 180, desc = "Un ballon postal s'est echappe. Attrape-le en vol !", color = Color3.fromRGB(255, 110, 130) },
		{ id = "Tournee", name = "Grande Tournee", duration = 240, desc = "Objectif commun : livrez ensemble avant la fin !", color = Color3.fromRGB(110, 220, 160), goalPerPlayer = 6, goalMin = 10 },
	},
}

Config.StartCoins = 0
Config.SeaLevel = 0
Config.SpawnPosition = Vector3.new(0, 66, 42)

return Config
