-- Capacites validees cote serveur (Pulse) et relais des effets (Dash).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local AbilityService = {}

local cooldowns = {} -- [player] = { [ability] = time }

local function onCooldown(player, name, duration)
	local now = os.clock()
	cooldowns[player] = cooldowns[player] or {}
	local last = cooldowns[player][name] or 0
	if now - last < duration then
		return true
	end
	cooldowns[player][name] = now
	return false
end

function AbilityService.Init(roundManager)
	Players.PlayerRemoving:Connect(function(player)
		cooldowns[player] = nil
	end)

	Remotes.Ability.OnServerEvent:Connect(function(player, name)
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if not hrp then
			return
		end

		if name == "Pulse" then
			if onCooldown(player, "Pulse", Config.Abilities.Pulse.Cooldown - 0.5) then
				return
			end
			local ball = roundManager.GetBall()
			if not ball or not roundManager.IsAlive(player) then
				return
			end
			local pos = ball:getPosition()
			if pos and (pos - hrp.Position).Magnitude <= Config.Abilities.Pulse.Radius then
				ball:slow(Config.Abilities.Pulse.Duration)
				Remotes.BallEvent:FireAllClients("Pulse", { userId = player.UserId, position = hrp.Position, hit = true })
			else
				Remotes.BallEvent:FireAllClients("Pulse", { userId = player.UserId, position = hrp.Position, hit = false })
			end
		elseif name == "Dash" then
			if onCooldown(player, "Dash", 0.5) then
				return
			end
			Remotes.BallEvent:FireAllClients("Dash", { userId = player.UserId })
		end
	end)

	Remotes.Deflect.OnServerEvent:Connect(function(player)
		if onCooldown(player, "DeflectSpam", 0.1) then
			return
		end
		roundManager.HandleDeflect(player)
	end)
end

return AbilityService
