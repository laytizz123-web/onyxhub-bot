-- Etat local du joueur (donnees synchronisees + colis en cours).
local State = {
	data = { coins = 0, xp = 0, rank = 1, xpIn = 0, xpNeed = 1, deliveries = 0, gliders = { Lin = true }, glider = "Lin", satchel = 1, trails = { Aucune = true }, trail = "Aucune", stamps = {}, dailyIn = 0, grades = {} },
	parcels = {},
	event = nil,
	ready = false,
}
State.Changed = Instance.new("BindableEvent") -- (what)
return State
