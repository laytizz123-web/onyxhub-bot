-- Controles : M1, blocage, dash directionnel, competences, ultimate, menus, boutons tactiles.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local State = require(script.Parent.State)
local Anim = require(script.Parent.Anim)

local Input = {}
local C = Config.Combat

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local function getChar()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid and hrp and humanoid.Health > 0 then
		return character, humanoid, hrp
	end
	return nil
end

local function isStunned(character)
	return (character:GetAttribute("StunUntil") or 0) > os.clock()
end

-- Oriente le personnage vers la camera (comme un shift-lock au moment de l'attaque)
local function faceCamera(hrp)
	local look = camera.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude > 0.01 then
		hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + flat.Unit)
	end
end

local lastM1 = 0
function Input.m1()
	local character, _, hrp = getChar()
	if not character or isStunned(character) or State.blocking then
		return
	end
	if os.clock() - lastM1 < C.M1Cooldown then
		return
	end
	lastM1 = os.clock()
	faceCamera(hrp)
	Remotes.Combat:FireServer("m1")
end

function Input.setBlock(enabled)
	local character = getChar()
	if not character then
		return
	end
	if enabled and isStunned(character) then
		return
	end
	if State.blocking == enabled then
		return
	end
	State.blocking = enabled
	Remotes.Combat:FireServer("block", enabled)
	State.fire("block", enabled)
end

local function dashDirection(humanoid, hrp)
	local move = humanoid.MoveDirection
	local look = camera.CFrame.LookVector
	local flatLook = Vector3.new(look.X, 0, look.Z)
	if flatLook.Magnitude < 0.01 then
		flatLook = hrp.CFrame.LookVector
	end
	flatLook = flatLook.Unit
	if move.Magnitude < 0.1 then
		return flatLook, "avant"
	end
	local right = Vector3.new(-flatLook.Z, 0, flatLook.X)
	local f = move:Dot(flatLook)
	local r = move:Dot(right)
	local name
	if math.abs(f) >= math.abs(r) then
		name = f > 0 and "avant" or "arriere"
	else
		name = r > 0 and "droite" or "gauche"
	end
	return move.Unit, name
end

function Input.dash()
	local character, humanoid, hrp = getChar()
	if not character or isStunned(character) then
		return
	end
	if os.clock() < State.dashReadyAt then
		return
	end
	State.dashReadyAt = os.clock() + C.DashCooldown
	local direction, name = dashDirection(humanoid, hrp)
	if State.blocking then
		Input.setBlock(false)
	end
	local attachment = hrp:FindFirstChild("RootAttachment") or Instance.new("Attachment", hrp)
	local lv = Instance.new("LinearVelocity")
	lv.Attachment0 = attachment
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.MaxForce = 1e6
	lv.VectorVelocity = direction * C.DashSpeed + Vector3.new(0, 4, 0)
	lv.Parent = hrp
	Debris:AddItem(lv, C.DashDuration)
	Anim.play(character, "dash")
	Remotes.Combat:FireServer("dash", name)
	State.fire("dash", name)
end

function Input.skill(slot)
	local character, _, hrp = getChar()
	if not character or isStunned(character) or State.blocking then
		return
	end
	local cd = State.cooldowns[slot]
	if cd and cd.untilTime > os.clock() then
		return
	end
	faceCamera(hrp)
	Remotes.Combat:FireServer("skill", slot)
end

function Input.ultimate()
	local character = getChar()
	if not character then
		return
	end
	if (character:GetAttribute("Ult") or 0) < 100 or character:GetAttribute("UltActive") then
		State.fire("notify", { text = "Ultimate pas encore charge.", kind = "info" })
		return
	end
	Remotes.Combat:FireServer("ult")
end

-- Reponse du serveur : cooldown + mouvement des rush
local function onSkillAck(data)
	State.cooldowns[data.slot] = { untilTime = os.clock() + data.cooldown, duration = data.cooldown }
	State.fire("cooldown", data.slot)
	if data.type == "rush" then
		task.delay(data.windup, function()
			local character, _, hrp = getChar()
			if not character or isStunned(character) then
				return
			end
			faceCamera(hrp)
			local attachment = hrp:FindFirstChild("RootAttachment") or Instance.new("Attachment", hrp)
			local lv = Instance.new("LinearVelocity")
			lv.Attachment0 = attachment
			lv.RelativeTo = Enum.ActuatorRelativeTo.World
			lv.MaxForce = 1e6
			lv.VectorVelocity = hrp.CFrame.LookVector * (data.distance / data.duration)
			lv.Parent = hrp
			Debris:AddItem(lv, data.duration)
		end)
	end
end

local function bind(name, handler, touch, ...)
	ContextActionService:BindAction(name, function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			handler()
		end
		return Enum.ContextActionResult.Pass
	end, touch, ...)
end

function Input.Init()
	Remotes.SkillAck.OnClientEvent:Connect(onSkillAck)

	local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

	bind("BG_M1", Input.m1, false, Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonR2)
	bind("BG_Dash", Input.dash, false, Enum.KeyCode.Q, Enum.KeyCode.ButtonL1)
	bind("BG_Ult", Input.ultimate, false, Enum.KeyCode.G, Enum.KeyCode.ButtonY)
	for slot = 1, 4 do
		local keys = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four }
		local pads = { Enum.KeyCode.ButtonX, Enum.KeyCode.ButtonB, Enum.KeyCode.ButtonA, Enum.KeyCode.ButtonR1 }
		bind("BG_Skill" .. slot, function()
			Input.skill(slot)
		end, false, keys[slot], pads[slot])
	end

	ContextActionService:BindAction("BG_Block", function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			Input.setBlock(true)
		elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
			Input.setBlock(false)
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.F, Enum.KeyCode.ButtonL2)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or input.UserInputType ~= Enum.UserInputType.Keyboard then
			return
		end
		if input.KeyCode == Enum.KeyCode.C then
			State.fire("toggle", "characters")
		elseif input.KeyCode == Enum.KeyCode.K then
			State.fire("toggle", "cosmetics")
		elseif input.KeyCode == Enum.KeyCode.Escape then
			State.fire("toggle", "close")
		end
	end)

	-- Le blocage s'arrete si on est stun (le serveur l'a deja annule)
	RunService.Heartbeat:Connect(function()
		local character = getChar()
		if character and State.blocking and not character:GetAttribute("Blocking") then
			State.blocking = false
			State.fire("block", false)
		end
	end)

	player.CharacterAdded:Connect(function()
		State.blocking = false
		State.cooldowns = {}
		State.fire("respawn")
	end)

	Input.touch = touch
end

return Input
