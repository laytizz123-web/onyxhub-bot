-- Etat partage cote client.

local State = {}

State.data = { coins = 0, totalCoins = 0, pets = {}, equipped = {}, zones = { Village = true }, index = {}, hatched = 0, raceWins = 0, races = 0, dailyReady = false, dailyIn = 0, power = 0 }
State.race = { phase = "Idle", racers = {} }
State.Changed = Instance.new("BindableEvent")

function State.fire(what, data)
	State.Changed:Fire(what, data)
end

function State.petByUid(uid)
	for _, pet in ipairs(State.data.pets) do
		if pet.uid == uid then
			return pet
		end
	end
	return nil
end

return State
