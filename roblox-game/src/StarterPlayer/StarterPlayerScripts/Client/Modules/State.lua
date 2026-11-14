-- Etat partage entre les modules client.

local State = {}

State.round = { phase = "Waiting", message = "", timer = 0, aliveCount = 0, totalCount = 0, practice = false, winnerUserId = 0 }
State.cooldowns = {} -- [name] = os.clock() de fin
State.targetUserId = 0
State.overdrive = false

State.Changed = Instance.new("BindableEvent") -- (what, data)

function State.setCooldown(name, duration)
	State.cooldowns[name] = os.clock() + duration
	State.Changed:Fire("cooldown", name)
end

function State.cooldownLeft(name)
	local untilTime = State.cooldowns[name]
	if not untilTime then
		return 0
	end
	return math.max(0, untilTime - os.clock())
end

function State.getBall()
	return workspace:FindFirstChild("ArenaBall")
end

return State
