-- Etat partage cote client.

local State = {}

State.stats = { xp = 0, level = 1, xpNext = 100, coins = 0, kills = 0, deaths = 0, wins = 0, character = "Fighter", aura = "none", trail = "none", title = "rookie", unlocked = { auras = {}, trails = {}, titles = {} } }
State.cooldowns = {} -- [slot] = { untilTime, duration }
State.dashReadyAt = 0
State.blocking = false
State.combo = 0
State.comboAt = 0

State.Changed = Instance.new("BindableEvent")

function State.fire(what, data)
	State.Changed:Fire(what, data)
end

return State
