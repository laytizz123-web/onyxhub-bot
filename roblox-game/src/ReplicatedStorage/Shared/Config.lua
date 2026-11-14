-- Configuration centrale d'ONYX ARENA.
-- Modifie ces valeurs pour equilibrer le jeu sans toucher au reste du code.

local Config = {}

Config.GameName = "ONYX ARENA"

Config.Round = {
	MinPlayers = 2, -- en dessous : mode entrainement automatique
	Intermission = 12,
	Countdown = 4,
	Duration = 150, -- secondes avant le mode OVERDRIVE
	EndDelay = 6,
}

Config.Ball = {
	BaseSpeed = 42,
	SpeedPerDeflect = 1.09, -- multiplicateur a chaque renvoi
	SpeedBonus = 2, -- bonus fixe a chaque renvoi
	MaxSpeed = 240,
	TurnRate = 5, -- reactivite du guidage (plus haut = plus dur a esquiver)
	HitRadius = 4.5,
	DeflectRange = 16, -- distance max pour renvoyer le ballon
	DeflectCooldown = 0.5,
	GraceTime = 0.35, -- temps d'invulnerabilite apres un changement de cible
	OverdriveMultiplier = 1.8,
	Size = 4,
	Height = 3, -- hauteur visee par rapport au centre du joueur
}

Config.Abilities = {
	Dash = { Cooldown = 4, Speed = 95, Lift = 8 },
	DoubleJump = { Power = 55 },
	Pulse = { Cooldown = 18, Duration = 2.5, SlowFactor = 0.3, Radius = 45 },
}

Config.Rewards = {
	Win = 75,
	Deflect = 2,
	Survive = 10,
	StreakBonus = 15,
}

Config.Arena = {
	Center = Vector3.new(0, 0, 0),
	Radius = 60,
	WallHeight = 26,
	WallSegments = 36,
	PillarCount = 8,
	PillarRadius = 32,
	JumpPadCount = 6,
	JumpPadRadius = 47,
	JumpPadPower = 95,
	SpawnRadius = 44,
	KillHeight = -40,
}

Config.Lobby = {
	Center = Vector3.new(0, 150, -170),
	Size = Vector3.new(80, 2, 80),
}

Config.Colors = {
	Accent = Color3.fromRGB(0, 229, 255),
	Accent2 = Color3.fromRGB(170, 0, 255),
	Danger = Color3.fromRGB(255, 60, 60),
	Gold = Color3.fromRGB(255, 200, 40),
	Dark = Color3.fromRGB(18, 18, 26),
	Floor = Color3.fromRGB(30, 30, 42),
}

return Config
