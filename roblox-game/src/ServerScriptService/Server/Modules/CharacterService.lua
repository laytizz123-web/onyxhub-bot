-- Applique la classe au personnage, gere la mort, le credit des eliminations.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local DataService = require(script.Parent.DataService)
local ProgressionService = require(script.Parent.ProgressionService)
local MapBuilder = require(script.Parent.MapBuilder)

local CharacterService = {}

local function applyClass(player, character)
	local data = DataService.Get(player)
	if not data then
		return
	end
	local def = Config.CharacterById[data.Character] or Config.Characters[1]
	local humanoid = character:WaitForChild("Humanoid", 5)
	if not humanoid then
		return
	end
	humanoid.MaxHealth = def.health
	humanoid.Health = def.health
	humanoid.WalkSpeed = def.walkSpeed
	humanoid.JumpPower = 50
	humanoid.UseJumpPower = true
	humanoid.BreakJointsOnDeath = false
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	character:SetAttribute("CharacterId", def.id)
	character:SetAttribute("BaseSpeed", def.walkSpeed)
	character:SetAttribute("StunUntil", 0)
	character:SetAttribute("Blocking", false)
	character:SetAttribute("Ult", 0)
	character:SetAttribute("UltActive", false)
	character:SetAttribute("LastDamager", 0)
	character:SetAttribute("LastDamageTime", 0)

	humanoid.Died:Connect(function()
		local killerId = character:GetAttribute("LastDamager") or 0
		local lastTime = character:GetAttribute("LastDamageTime") or 0
		local killer = killerId ~= 0 and Players:GetPlayerByUserId(killerId) or nil
		Remotes.CombatFX:FireAllClients("Death", { userId = player.UserId, position = character:GetPivot().Position })
		if killer and killer ~= player and os.clock() - lastTime < 10 then
			ProgressionService.OnKill(killer, player)
		else
			Remotes.Notify:FireAllClients(player.DisplayName .. " est mort.", "info")
		end
		ProgressionService.OnDeath(player)
	end)
end

local function onCharacterAdded(player, character)
	task.wait(0.1)
	applyClass(player, character)
	-- Chute hors de la map
	task.spawn(function()
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		while character.Parent and humanoid and humanoid.Health > 0 do
			task.wait(0.5)
			local hrp = character:FindFirstChild("HumanoidRootPart")
			if hrp and hrp.Position.Y < Config.Map.KillHeight then
				humanoid.Health = 0
			end
		end
	end)
end

local function onPlayerAdded(player)
	DataService.Load(player)
	player:SetAttribute("Streak", 0)
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		onCharacterAdded(player, player.Character)
	end
	task.wait(1)
	if player.Parent == Players then
		ProgressionService.SyncStats(player)
		Remotes.Notify:FireClient(player, "Bienvenue sur " .. Config.GameName .. " ! Appuie sur C pour choisir ton personnage.", "good")
	end
end

-- Recharge le personnage (changement de classe) : seulement en zone sure ou mort
function CharacterService.Reload(player)
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if hrp and humanoid and humanoid.Health > 0 and not MapBuilder.IsSafe(hrp.Position) then
		Remotes.Notify:FireClient(player, "Le personnage sera applique a ta prochaine apparition (retourne au spawn pour changer tout de suite).", "info")
		return
	end
	player:LoadCharacter()
end

function CharacterService.RefreshCosmetics(player)
	-- Les attributs Aura / Trail / Title sont sur le joueur : les clients les lisent directement.
end

-- Mannequins : credit XP seulement (pas de kill)
local function hookDummy(model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Died:Connect(function()
			Remotes.CombatFX:FireAllClients("Death", { userId = 0, position = model:GetPivot().Position })
		end)
	end
end

function CharacterService.Init()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, p in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, p)
	end
	Players.PlayerRemoving:Connect(function(player)
		DataService.Save(player)
		DataService.Release(player)
	end)
	for _, dummy in ipairs(CollectionService:GetTagged("Dummy")) do
		hookDummy(dummy)
	end
	CollectionService:GetInstanceAddedSignal("Dummy"):Connect(hookDummy)
end

return CharacterService
