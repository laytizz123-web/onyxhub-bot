-- Configuration centrale d'ONYX BATTLEGROUNDS.
-- Personnages, competences, progression, cosmetiques : tout l'equilibrage est ici.

local Config = {}

Config.GameName = "ONYX BATTLEGROUNDS"

Config.Colors = {
	Accent = Color3.fromRGB(0, 229, 255),
	Accent2 = Color3.fromRGB(255, 90, 40),
	Gold = Color3.fromRGB(255, 200, 40),
	Danger = Color3.fromRGB(255, 60, 60),
	Dark = Color3.fromRGB(16, 18, 26),
	Health = Color3.fromRGB(80, 230, 110),
	Ult = Color3.fromRGB(200, 80, 255),
	Panel = Color3.fromRGB(22, 24, 36),
	Panel2 = Color3.fromRGB(10, 12, 20),
}

Config.Icons = {
	coins = "🪙",
	xp = "✨",
	kills = "💀",
	wins = "🏆",
	deaths = "☠️",
	dash = "💨",
	block = "🛡️",
	ult = "🌟",
	m1 = "👊",
	level = "⬆️",
	character = "🎭",
	cosmetics = "🎨",
	aura = "🔮",
	trail = "🌠",
	title = "📜",
	safe = "🏠",
	warning = "⚠️",
}

Config.Combat = {
	M1Cooldown = 0.32, -- delai entre deux coups
	ComboReset = 1.1, -- temps avant que le combo retombe a 0
	ComboEndCooldown = 0.9, -- delai apres le 4e coup
	M1Range = 7,
	M1Hitbox = Vector3.new(6, 6, 7),
	HitStun = 0.45,
	FinisherStun = 1.2,
	FinisherKnockback = 55,
	BlockReduction = 0.7, -- 70 % de degats en moins
	BlockSkillReduction = 0.5,
	BlockMoveSpeed = 6,
	DashCooldown = 1.6,
	DashSpeed = 85,
	DashDuration = 0.22,
	UltPerDamageDealt = 0.55, -- points d'ultimate par point de degats infliges
	UltPerDamageTaken = 0.3,
	UltDuration = 16,
	UltDamageMultiplier = 1.25,
	RespawnTime = 4,
	StreakForWin = 3, -- 3 eliminations d'affilee = 1 victoire
}

-- Types de competence :
--  melee      : coup au corps a corps (hitbox devant le joueur apres windup)
--  rush       : fonce vers l'avant en frappant tout sur le passage
--  projectile : tir vers l'avant, degats a l'impact (+ zone optionnelle)
--  aoe        : explosion autour du joueur
--  buff       : bonus temporaire (vitesse)
-- Champs : name, type, damage, cooldown, windup, range/radius, knockback, lift, stun,
--          knockdown, color, pose (animation procedurale), sound, speed (projectile/rush)
Config.Characters = {
	{
		id = "Fighter",
		name = "Fighter",
		icon = "🥊",
		description = "Equilibre et facile a prendre en main.",
		color = Color3.fromRGB(255, 200, 60),
		health = 100,
		walkSpeed = 17,
		m1Damage = 8,
		m1Finisher = 13,
		skills = {
			{ name = "Uppercut", icon = "👊", type = "melee", damage = 18, cooldown = 6, windup = 0.25, range = 8, knockback = 20, lift = 45, stun = 0.8, pose = "uppercut", sound = "heavy" },
			{ name = "Rush Punch", icon = "💨", type = "rush", damage = 20, cooldown = 9, windup = 0.1, distance = 32, duration = 0.35, knockback = 40, stun = 0.7, pose = "rush", sound = "whoosh" },
			{ name = "Shockwave", icon = "💥", type = "aoe", damage = 16, cooldown = 11, windup = 0.45, radius = 13, knockback = 45, lift = 20, stun = 0.8, pose = "slam", sound = "slam" },
			{ name = "Finisher", icon = "☄️", type = "melee", damage = 34, cooldown = 18, windup = 0.5, range = 9, knockback = 70, lift = 15, stun = 1.4, knockdown = true, pose = "heavy", sound = "heavy" },
		},
		ultSkills = {
			{ name = "Meteor Fist", icon = "☄️", type = "melee", damage = 40, cooldown = 6, windup = 0.3, range = 10, knockback = 60, lift = 30, stun = 1.2, knockdown = true, pose = "heavy", sound = "heavy" },
			{ name = "Blitz Rush", icon = "🌀", type = "rush", damage = 34, cooldown = 7, windup = 0.05, distance = 44, duration = 0.3, knockback = 50, stun = 0.9, pose = "rush", sound = "whoosh" },
			{ name = "Earth Breaker", icon = "🌋", type = "aoe", damage = 32, cooldown = 9, windup = 0.5, radius = 17, knockback = 60, lift = 35, stun = 1.1, pose = "slam", sound = "slam" },
			{ name = "Omega Strike", icon = "💫", type = "melee", damage = 65, cooldown = 16, windup = 0.65, range = 11, knockback = 95, lift = 25, stun = 1.8, knockdown = true, pose = "heavy", sound = "heavy" },
		},
	},
	{
		id = "Volt",
		name = "Volt",
		icon = "⚡",
		description = "Rapide, specialise dans les deplacements.",
		color = Color3.fromRGB(80, 200, 255),
		health = 85,
		walkSpeed = 21,
		m1Damage = 7,
		m1Finisher = 11,
		skills = {
			{ name = "Spark Jab", icon = "⚡", type = "melee", damage = 12, cooldown = 4, windup = 0.1, range = 8, knockback = 15, stun = 0.6, pose = "jab", sound = "zap" },
			{ name = "Lightning Dash", icon = "🌩️", type = "rush", damage = 18, cooldown = 7, windup = 0.05, distance = 42, duration = 0.28, knockback = 30, stun = 0.7, pose = "rush", sound = "zap" },
			{ name = "Thunder Bolt", icon = "🔆", type = "projectile", damage = 22, cooldown = 8, windup = 0.2, speed = 140, lifetime = 1.5, radius = 5, knockback = 35, stun = 0.8, pose = "cast", sound = "zap" },
			{ name = "Overcharge", icon = "🔋", type = "buff", cooldown = 22, windup = 0.1, duration = 8, speedMultiplier = 1.5, pose = "power", sound = "charge" },
		},
		ultSkills = {
			{ name = "Chain Lightning", icon = "⛓️", type = "aoe", damage = 26, cooldown = 6, windup = 0.25, radius = 15, knockback = 35, lift = 20, stun = 0.9, pose = "power", sound = "zap" },
			{ name = "Volt Rush", icon = "🌪️", type = "rush", damage = 30, cooldown = 6, windup = 0.05, distance = 55, duration = 0.3, knockback = 45, stun = 0.8, pose = "rush", sound = "zap" },
			{ name = "Plasma Shot", icon = "🔮", type = "projectile", damage = 42, cooldown = 8, windup = 0.2, speed = 160, lifetime = 1.6, radius = 9, knockback = 50, stun = 1, pose = "cast", sound = "zap" },
			{ name = "Storm Cage", icon = "🌐", type = "aoe", damage = 48, cooldown = 15, windup = 0.6, radius = 19, knockback = 20, lift = 50, stun = 1.6, knockdown = true, pose = "slam", sound = "thunder" },
		},
	},
	{
		id = "Titan",
		name = "Titan",
		icon = "🪨",
		description = "Lent mais devastateur.",
		color = Color3.fromRGB(170, 120, 90),
		health = 145,
		walkSpeed = 14,
		m1Damage = 11,
		m1Finisher = 16,
		skills = {
			{ name = "Boulder Punch", icon = "🪨", type = "melee", damage = 26, cooldown = 7, windup = 0.4, range = 9, knockback = 55, lift = 15, stun = 1, pose = "heavy", sound = "heavy" },
			{ name = "Charge", icon = "🐂", type = "rush", damage = 28, cooldown = 10, windup = 0.3, distance = 28, duration = 0.45, knockback = 60, stun = 1, knockdown = true, pose = "rush", sound = "whoosh" },
			{ name = "Ground Slam", icon = "🌍", type = "aoe", damage = 30, cooldown = 13, windup = 0.6, radius = 14, knockback = 50, lift = 40, stun = 1.2, knockdown = true, pose = "slam", sound = "slam" },
			{ name = "Titan Crush", icon = "🏔️", type = "melee", damage = 46, cooldown = 20, windup = 0.7, range = 10, knockback = 90, lift = 30, stun = 1.8, knockdown = true, pose = "heavy", sound = "slam" },
		},
		ultSkills = {
			{ name = "Quake", icon = "🌋", type = "aoe", damage = 40, cooldown = 7, windup = 0.4, radius = 18, knockback = 60, lift = 45, stun = 1.2, knockdown = true, pose = "slam", sound = "slam" },
			{ name = "Avalanche", icon = "🏔️", type = "rush", damage = 45, cooldown = 8, windup = 0.2, distance = 40, duration = 0.45, knockback = 80, stun = 1.2, knockdown = true, pose = "rush", sound = "whoosh" },
			{ name = "Mountain Fist", icon = "⛰️", type = "melee", damage = 72, cooldown = 10, windup = 0.55, range = 11, knockback = 100, lift = 40, stun = 1.8, knockdown = true, pose = "heavy", sound = "heavy" },
			{ name = "Cataclysm", icon = "🌑", type = "aoe", damage = 85, cooldown = 18, windup = 0.9, radius = 24, knockback = 110, lift = 60, stun = 2.2, knockdown = true, pose = "slam", sound = "thunder" },
		},
	},
	{
		id = "Blaze",
		name = "Blaze",
		icon = "🔥",
		description = "Specialiste des attaques a distance.",
		color = Color3.fromRGB(255, 110, 30),
		health = 90,
		walkSpeed = 17,
		m1Damage = 7,
		m1Finisher = 12,
		skills = {
			{ name = "Fire Punch", icon = "🔥", type = "melee", damage = 17, cooldown = 6, windup = 0.2, range = 8, knockback = 30, lift = 10, stun = 0.8, pose = "jab", sound = "fire" },
			{ name = "Flame Dash", icon = "🎇", type = "rush", damage = 20, cooldown = 8, windup = 0.1, distance = 36, duration = 0.32, knockback = 40, stun = 0.8, pose = "rush", sound = "fire" },
			{ name = "Fire Blast", icon = "🎯", type = "projectile", damage = 26, cooldown = 9, windup = 0.25, speed = 110, lifetime = 1.8, radius = 7, knockback = 40, lift = 15, stun = 0.9, pose = "cast", sound = "fire" },
			{ name = "Inferno", icon = "🔥", type = "aoe", damage = 36, cooldown = 17, windup = 0.7, radius = 15, knockback = 55, lift = 30, stun = 1.3, knockdown = true, pose = "power", sound = "explosion" },
		},
		ultSkills = {
			{ name = "Hellfire Fist", icon = "😈", type = "melee", damage = 36, cooldown = 5, windup = 0.2, range = 9, knockback = 45, lift = 20, stun = 1, pose = "jab", sound = "fire" },
			{ name = "Phoenix Dash", icon = "🐦‍🔥", type = "rush", damage = 42, cooldown = 7, windup = 0.05, distance = 50, duration = 0.3, knockback = 55, stun = 1, pose = "rush", sound = "fire" },
			{ name = "Dragon Breath", icon = "🐉", type = "projectile", damage = 55, cooldown = 8, windup = 0.3, speed = 120, lifetime = 2, radius = 12, knockback = 60, lift = 25, stun = 1.2, knockdown = true, pose = "cast", sound = "explosion" },
			{ name = "Supernova", icon = "🌟", type = "aoe", damage = 90, cooldown = 18, windup = 1, radius = 26, knockback = 100, lift = 60, stun = 2, knockdown = true, pose = "power", sound = "thunder" },
		},
	},
}

Config.CharacterById = {}
for _, char in ipairs(Config.Characters) do
	Config.CharacterById[char.id] = char
end

Config.Progression = {
	XPPerHit = 2,
	XPPerKill = 60,
	XPPerWin = 120,
	CoinsPerHit = 1,
	CoinsPerKill = 40,
	CoinsPerWin = 120,
	-- XP necessaire pour passer du niveau n au niveau n+1
	XPForLevel = function(level)
		return math.floor(120 + 60 * (level ^ 1.4))
	end,
	MaxLevel = 100,
}

-- Cosmetiques
Config.Auras = {
	{ id = "none", name = "Aucune", price = 0 },
	{ id = "cyan", name = "Aura Cyan", price = 300, color = Color3.fromRGB(0, 229, 255) },
	{ id = "fire", name = "Aura Feu", price = 800, color = Color3.fromRGB(255, 110, 30) },
	{ id = "toxic", name = "Aura Toxique", price = 1500, color = Color3.fromRGB(120, 255, 60) },
	{ id = "void", name = "Aura Neant", price = 3000, color = Color3.fromRGB(150, 60, 255) },
	{ id = "gold", name = "Aura Or", price = 6000, color = Color3.fromRGB(255, 215, 0) },
}
Config.Trails = {
	{ id = "none", name = "Aucune", price = 0 },
	{ id = "white", name = "Trainee Blanche", price = 200, color = Color3.new(1, 1, 1) },
	{ id = "blue", name = "Trainee Bleue", price = 600, color = Color3.fromRGB(60, 140, 255) },
	{ id = "red", name = "Trainee Rouge", price = 1200, color = Color3.fromRGB(255, 60, 60) },
	{ id = "rainbow", name = "Trainee Arc-en-ciel", price = 4000, color = Color3.fromRGB(255, 120, 255) },
}
-- Titres : debloques par niveau, kills ou victoires
Config.Titles = {
	{ id = "rookie", name = "Debutant", requirement = { kind = "level", value = 1 } },
	{ id = "fighter", name = "Combattant", requirement = { kind = "level", value = 5 } },
	{ id = "veteran", name = "Veteran", requirement = { kind = "level", value = 10 } },
	{ id = "elite", name = "Elite", requirement = { kind = "level", value = 20 } },
	{ id = "legend", name = "Legende", requirement = { kind = "level", value = 35 } },
	{ id = "slayer", name = "Tueur", requirement = { kind = "kills", value = 50 } },
	{ id = "executioner", name = "Bourreau", requirement = { kind = "kills", value = 250 } },
	{ id = "champion", name = "Champion", requirement = { kind = "wins", value = 10 } },
	{ id = "unstoppable", name = "Inarretable", requirement = { kind = "wins", value = 50 } },
}

Config.Map = {
	SpawnPosition = Vector3.new(0, 3, 150),
	ArenaCenter = Vector3.new(0, 0, 0),
	ArenaRadius = 42,
	CityOrigin = Vector3.new(0, 0, -120),
	CalmZone = Vector3.new(170, 0, 90),
	DummyCount = 4,
	DummyHealth = 600,
	KillHeight = -40,
}

return Config
