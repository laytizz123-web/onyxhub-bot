-- Etat partage entre les modules client.

local State = {}

State.inventory = { coins = 0, seeds = {}, fruits = {}, fruitValue = 0, plotId = 0, expandLevel = 0, expandPrice = nil, harvests = 0 }
State.shop = { stock = {}, nextRestock = 0 }
State.weather = { id = "Clair", label = "", endsAt = 0 }
State.selectedSeed = nil
State.waterReadyAt = 0

State.Changed = Instance.new("BindableEvent") -- (what, data)

function State.fire(what, data)
	State.Changed:Fire(what, data)
end

return State
