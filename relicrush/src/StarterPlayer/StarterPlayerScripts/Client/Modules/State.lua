-- Etat local : donnees du joueur, boss, echange en cours.
local State = {
	data = nil,
	extra = { power = 0, discovered = 0, count = 0, serverTime = os.time() },
	syncClock = os.clock(),
	boss = {},
	bossTime = os.time(),
	trade = nil,
	requests = {},
}
State.Changed = Instance.new("BindableEvent") -- ("data" | "boss" | "trade")

function State.Now()
	return State.extra.serverTime + (os.clock() - State.syncClock)
end

return State
